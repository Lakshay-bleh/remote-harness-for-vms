import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'actions.dart';
import 'apps.dart';
import 'commands.dart';
import 'contacts.dart';
import 'wake_status.dart';

/// The phone side of the assistant: apps, calls, alarms, torch, volume, settings, phone control and "Hey Escanor". A MethodChannel
/// to EscanorDevicePlugin (android/.../EscanorDevicePlugin.kt) and its iOS counterpart (ios/Runner/EscanorDevicePlugin.swift), with
/// the same method names and answers as the Capacitor plugin it replaces.
const deviceChannel = MethodChannel('escanor/device');

bool get isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

bool get isIOS {
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}

class ChannelDevice implements DevicePlugin {
  ChannelDevice._() {
    deviceChannel.setMethodCallHandler(_fromNative);
  }
  static final ChannelDevice instance = ChannelDevice._();

  final StreamController<void> _wake = StreamController<void>.broadcast();
  final StreamController<int> _progress = StreamController<int>.broadcast();
  final StreamController<void> _voiceLink = StreamController<void>.broadcast();

  /// "Hey Escanor" was heard while the app is showing.
  Stream<void> get wakeHeard => _wake.stream;

  /// The voice model download, 0 to 100.
  Stream<int> get modelProgress => _progress.stream;

  /// The app was opened with escanor://voice (the "Hey! I'm listening" notification, or opened directly while phone control is on). Take it with [takeVoiceLink].
  Stream<void> get voiceLinks => _voiceLink.stream;

  Future<Object?> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'wake':
        _wake.add(null);
      case 'wakeModelProgress':
        final a = call.arguments;
        _progress.add(a is Map && a['percent'] is num ? (a['percent'] as num).toInt() : 0);
      case 'voiceLink':
        _voiceLink.add(null);
    }
    return null;
  }

  Future<Object?> _call(String method, [Map<String, Object?>? args]) => deviceChannel.invokeMethod<Object?>(method, args);
  Future<PluginResult> _result(String method, [Map<String, Object?>? args]) async => PluginResult.fromJson(await _call(method, args));

  @override
  Future<List<InstalledApp>> listApps() async {
    final r = await _call('listApps');
    final apps = r is Map ? r['apps'] : null;
    return [for (final a in apps is List ? apps : const []) if (a is Map) InstalledApp.fromJson(a)];
  }

  @override
  Future<PluginResult> launchPackage(String package) => _result('launchPackage', {'package': package});
  @override
  Future<PluginResult> openUrl(String url) => _result('openUrl', {'url': url});
  @override
  Future<PluginResult> dial(String number) => _result('dial', {'number': number});
  @override
  Future<PluginResult> callNumber(String number, {required bool direct}) => _result('callNumber', {'number': number, 'direct': direct});
  @override
  Future<PluginResult> callContact(String name, {bool? direct}) => _result('callContact', {'name': name, 'direct': ?direct});

  @override
  Future<({PluginResult result, List<Contact> contacts})>? listContacts() => () async {
        final r = await _call('listContacts');
        final list = r is Map ? r['contacts'] : null;
        return (result: PluginResult.fromJson(r), contacts: [for (final c in list is List ? list : const []) if (c is Map) Contact.fromJson(c)]);
      }();

  @override
  Future<({bool granted, bool? available})> callStatus() async {
    final r = await _call('callStatus');
    final available = r is Map ? r['available'] : null;
    return (granted: r is Map && r['granted'] == true, available: available is bool ? available : null);
  }

  @override
  Future<PluginResult> requestCallPermission() => _result('requestCallPermission');
  @override
  Future<ControlStatus> controlStatus() async => ControlStatus.fromJson(await _call('controlStatus'));
  @override
  Future<PluginResult> openControlSettings() => _result('openControlSettings');
  @override
  Future<PluginResult> controlTurnOff() => _result('controlTurnOff');
  @override
  Future<PluginResult> openAppInfo() => _result('openAppInfo');
  @override
  Future<PluginResult> control(ControlRequest request) => _result('control', request.toJson());
  @override
  Future<PluginResult> setAlarm(int hour, int minute) => _result('setAlarm', {'hour': hour, 'minute': minute});
  @override
  Future<PluginResult> setTimer(int seconds) => _result('setTimer', {'seconds': seconds});
  @override
  Future<PluginResult> setTorch(bool on) => _result('setTorch', {'on': on});
  @override
  Future<PluginResult> setVolume(VolumeChange change) => _result('setVolume', {'change': change.name});
  @override
  Future<PluginResult> openSettings(SettingsScreen? screen) => _result('openSettings', {'screen': screen?.name ?? 'main'});

  // ---- "Hey Escanor" (Android only; iOS answers wakeStatus with everything off)

  Future<WakeStatus?> wakeStatus() async {
    if (!isAndroid) return null;
    try {
      return WakeStatus.fromJson(await _call('wakeStatus'));
    } catch (_) {
      return null;
    }
  }

  /// Download the voice model, with progress from 0 to 100.
  Future<PluginResult> wakeDownloadModel(void Function(int percent) onProgress) async {
    final sub = modelProgress.listen(onProgress);
    try {
      return await _result('wakeDownloadModel');
    } finally {
      await sub.cancel();
    }
  }

  Future<PluginResult> wakeStart() => _result('wakeStart');
  Future<PluginResult> wakeStop() => _result('wakeStop');

  /// Voice mode has the microphone while it is open.
  Future<void> wakePause(bool paused) async {
    if (!isAndroid) return;
    try {
      await _call('wakePause', {'paused': paused});
    } catch (_) {}
  }

  Future<PluginResult> wakeDeleteModel() => _result('wakeDeleteModel');
  Future<PluginResult> wakeOpenFullScreenSettings() => _result('wakeOpenFullScreenSettings');

  /// Act as though the phrase was heard in six seconds, so it can be tried from another app.
  Future<PluginResult> wakeTest() => _result('wakeTest');

  /// Tell the native side whether the app is there to hear "wake" (it raises a notification instead when nobody is).
  Future<void> wakeListen(bool on) async {
    if (!isAndroid) return;
    try {
      await _call('wakeListen', {'on': on});
    } catch (_) {}
  }

  /// True once if the app was opened with escanor://voice since the last time this was asked.
  Future<bool> takeVoiceLink() async {
    if (!isAndroid) return false;
    try {
      return await deviceChannel.invokeMethod<bool>('takeVoiceLink') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// The phone's tools, or null where there is no phone (tests, desktop).
DevicePlugin? deviceOrNull() => isAndroid || isIOS ? ChannelDevice.instance : null;
