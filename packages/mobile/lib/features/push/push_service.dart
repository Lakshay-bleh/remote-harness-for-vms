import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/storage.dart';
import 'push_logic.dart';

export 'push_logic.dart';

/// Push notifications through Firebase Cloud Messaging. Firebase may not be configured in a build (no google-services.json /
/// GoogleService-Info.plist): every call here is guarded, so the app runs as normal and push is simply unavailable.

bool _firebaseReady = false;

/// Firebase started, so this build can receive push.
bool get firebaseReady => _firebaseReady;

bool get _isPhone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get _isAndroid => !kIsWeb && Platform.isAndroid;
bool get _isIOS => !kIsWeb && Platform.isIOS;

/// A message arriving while the app is in the background or closed. The system shows notification messages itself; this only
/// has to exist (and start Firebase in its own isolate) so data messages do not crash the app.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
}

/// Before the first frame: start Firebase if this build has it, and forget this phone's address on sign-out.
Future<void> startPush() async {
  if (!signOutHooks.contains(forgetPush)) signOutHooks.add(forgetPush);
  if (!_isPhone) return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    _firebaseReady = true;
  } catch (_) {
    _firebaseReady = false; // built without Firebase's config: push is unavailable, everything else works
    return;
  }
  try {
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  } catch (_) {}
}

Future<PushState> _permission() async {
  if (_isAndroid) {
    final s = await Permission.notification.status;
    if (s.isGranted || s.isLimited || s.isProvisional) return PushState.on;
    if (s.isPermanentlyDenied || s.isRestricted) return PushState.denied;
    return PushState.off; // not asked yet, or refused once: Android will still ask
  }
  final s = await FirebaseMessaging.instance.getNotificationSettings();
  return switch (s.authorizationStatus) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushState.on,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushState.denied,
    AuthorizationStatus.notDetermined => PushState.off,
  };
}

/// Where push stands on this phone, without asking anything.
Future<PushState> pushState() async {
  if (!_isPhone) return PushState.unsupported;
  if (!_firebaseReady) return PushState.unavailable;
  try {
    return await _permission();
  } catch (_) {
    return PushState.unavailable;
  }
}

final _local = FlutterLocalNotificationsPlugin();

AndroidFlutterLocalNotificationsPlugin? get _android =>
    _isAndroid ? _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>() : null;

/// Android 8+ shows nothing without a channel; this one is high importance so approvals make a sound.
Future<void> _createChannel() async {
  try {
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    ));
  } catch (_) {}
}

/// Ask Android how the Alerts channel is set right now (the person can change it in the phone's settings at any time).
Future<ChannelState?> alertChannelState() async {
  final android = _android;
  if (android == null) return null;
  try {
    final channels = await android.getNotificationChannels();
    return channelState(channels?.map((c) => (id: c.id, importance: c.importance.value)).toList());
  } catch (_) {
    return null;
  }
}

String? _storedToken() {
  try {
    return Storage.instance.getString(tokenKey);
  } catch (_) {
    return null;
  }
}

void _remember(String? token) {
  try {
    Storage.instance.setString(tokenKey, token);
  } catch (_) {
    // best effort: without it, forgetting this phone on sign-out is left to the server dropping dead tokens
  }
}

/// Tell Escanor this phone's push address.
Future<void> registerPushToken(String token) =>
    api.post('/users/me/push-token', {'token': token, 'platform': pushPlatform(ios: _isIOS)});

Future<void> unregisterPushToken(String token) => api.delete('/users/me/push-token', {'token': token});

/// Whether the server can send push at all, and to how many phones.
Future<({bool configured, int devices})> fetchPushStatus() async {
  final r = await api.get('/users/me/push-status') as Map<String, dynamic>;
  return (configured: r['configured'] == true, devices: (r['devices'] as num?)?.toInt() ?? 0);
}

/// Send a test notification to every phone of this person. Returns how many it reached.
Future<int> sendTestPush() async {
  final r = await api.post('/users/me/push-test') as Map<String, dynamic>?;
  return (r?['delivered'] as num?)?.toInt() ?? 0;
}

StreamSubscription<String>? _refreshSub;

Future<String?> _token() async {
  final m = FirebaseMessaging.instance;
  if (_isIOS) {
    // On iPhone the Firebase token needs Apple's push token first, which can take a moment after permission is given.
    for (var i = 0; i < 10 && await m.getAPNSToken() == null; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  return m.getToken();
}

/// Send this phone's address to Escanor now, and again whenever Firebase hands out a new one.
Future<void> _register() async {
  _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
    _remember(t);
    registerPushToken(t).catchError((_) {}); // retried at the next start
  }, onError: (_) {});
  final token = await _token();
  if (token == null || token.isEmpty) throw StateError('no token');
  _remember(token);
  try {
    await registerPushToken(token);
  } catch (_) {
    // retried at the next start
  }
}

/// Ask the person's permission (Android 13+, iPhone), then register this phone. Returns where that left things.
Future<PushState> enablePush() async {
  if (!_isPhone) return PushState.unsupported;
  if (!_firebaseReady) return PushState.unavailable;
  try {
    var p = await _permission();
    if (p != PushState.on) {
      if (_isAndroid) {
        await Permission.notification.request();
      } else {
        await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      }
      p = await _permission();
    }
    if (p != PushState.on) return p;
    await _createChannel();
    await _register();
    return PushState.on;
  } catch (_) {
    return PushState.unavailable;
  }
}

/// At app start: if they already said yes, register again (the address may have changed). Never asks.
Future<void> resumePush() async {
  if (await pushState() == PushState.on) await enablePush();
}

/// On sign-out: tell Escanor to stop sending this phone anything, so the next person to use it does not get these alerts.
Future<void> forgetPush() async {
  final token = _storedToken();
  _remember(null);
  await _refreshSub?.cancel();
  _refreshSub = null;
  if (token != null && token.isNotEmpty) {
    try {
      await unregisterPushToken(token);
    } catch (_) {}
  }
  if (_firebaseReady) {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

/// A notification that arrived while the app is open.
class ForegroundPush {
  ForegroundPush({required this.title, required this.body, required this.dest});
  final String title;
  final String body;
  final PushDest dest;
}

bool _launchHandled = false;

/// Tapping a notification, and one arriving while the app is open. Returns how to stop listening.
VoidCallback listenPush(void Function(PushDest dest) onOpen, void Function(ForegroundPush n) onForeground) {
  if (!_firebaseReady) return () {};
  final subs = <StreamSubscription<RemoteMessage>>[];
  try {
    subs.add(FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen(routeFor(m.data)), onError: (_) {}));
    subs.add(FirebaseMessaging.onMessage.listen(
      (m) => onForeground(ForegroundPush(title: m.notification?.title ?? 'Escanor', body: m.notification?.body ?? '', dest: routeFor(m.data))),
      onError: (_) {},
    ));
    if (!_launchHandled) {
      _launchHandled = true; // the notification that opened the app counts once, not again after signing back in
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) onOpen(routeFor(m.data));
      }).catchError((_) {});
    }
  } catch (_) {}
  return () {
    for (final s in subs) {
      s.cancel();
    }
  };
}
