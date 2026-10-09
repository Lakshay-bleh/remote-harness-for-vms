import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'cache.dart';
import 'config.dart';
import 'pkce.dart';
import 'storage.dart';

class EscanorUser {
  EscanorUser({required this.id, required this.email, required this.name, this.avatarUrl});
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;

  factory EscanorUser.fromJson(Map<String, dynamic> j) => EscanorUser(
        id: '${j['id'] ?? ''}',
        email: '${j['email'] ?? ''}',
        name: '${j['name'] ?? ''}',
        avatarUrl: j['avatar_url'] as String?,
      );
  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name, 'avatar_url': avatarUrl};
}

enum SessionStatus { loading, signedOut, signedIn }

@immutable
class SessionState {
  const SessionState({required this.status, this.user, this.error, this.busy = false});
  final SessionStatus status;
  final EscanorUser? user;
  final String? error;
  final bool busy;

  SessionState copyWith({SessionStatus? status, EscanorUser? user, bool clearUser = false, String? error, bool clearError = false, bool? busy}) =>
      SessionState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

/// The person's own details, remembered so the app opens signed in even when Escanor cannot be reached.
const _userCache = CachePolicy('user', ttl: Duration.zero, maxAge: Duration(days: 90));
const _pkceKey = 'rh_escanor_pkce_verifier';

/// Work to do when the person signs out (forget push token, device keys of computers, ...). Features
/// register here at start; each runs before the tokens are dropped and failures are ignored.
final List<Future<void> Function()> signOutHooks = [];

/// `escanor://auth/login?code=...` -> the code.
({String? code, String? error})? codeFromDeepLink(Uri uri) {
  if (uri.scheme != appScheme || uri.host != 'auth') return null;
  return (code: uri.queryParameters['code'], error: uri.queryParameters['error']);
}

class SessionNotifier extends Notifier<SessionState> {
  final Set<String> _handled = {};

  @override
  SessionState build() {
    api.onSessionEnded = sessionEnded;
    final has = api.tokens.hasSession;
    if (has) Future.microtask(load);
    return SessionState(status: has ? SessionStatus.loading : SessionStatus.signedOut);
  }

  Future<void> load() async {
    try {
      final me = await fetchMe();
      writeCache(_userCache.key, me.toJson());
      state = SessionState(status: SessionStatus.signedIn, user: me);
    } on SessionEnded {
      clearCache();
      state = const SessionState(status: SessionStatus.signedOut);
    } catch (e) {
      // The server or network having a moment is not the sign-in ending: stay in with the remembered details.
      final hit = api.tokens.hasSession ? readCache(_userCache) : null;
      if (hit != null && hit.value is Map) {
        state = SessionState(status: SessionStatus.signedIn, user: EscanorUser.fromJson(Map<String, dynamic>.from(hit.value as Map)));
      } else {
        state = SessionState(status: SessionStatus.signedOut, error: errorText(e, 'Could not sign in.'));
      }
    }
  }

  static Future<EscanorUser> fetchMe() async {
    final s = await api.get('/auth/session') as Map<String, dynamic>;
    return EscanorUser.fromJson(Map<String, dynamic>.from(s['user'] as Map));
  }

  String? _takeVerifier() {
    final v = Storage.instance.secret(_pkceKey);
    Storage.instance.setSecret(_pkceKey, null);
    return v;
  }

  /// A login code from the Google return link or from email sign-in: trade it for tokens.
  Future<void> finishSignIn(String code) async {
    if (!_handled.add(code)) return; // a login code works once; the same link can arrive twice
    state = state.copyWith(busy: true, clearError: true);
    try {
      clearCache();
      final verifier = _takeVerifier();
      final t = await api.post('/auth/oauth/exchange', {
        'code': code,
        'provider': 'google',
        'client': 'mobile',
        'code_verifier': ?verifier,
      }, false) as Map<String, dynamic>;
      api.tokens.set(t['access_token'] as String, t['refresh_token'] as String, (t['expires_in'] as num?)?.toInt());
      await load();
    } catch (e) {
      state = SessionState(status: SessionStatus.signedOut, error: errorText(e, 'Sign-in failed. Please try again.'));
    } finally {
      state = state.copyWith(busy: false);
      unawaited(closeInAppWebView().catchError((_) {}));
    }
  }

  /// A link the app was opened with. Returns true when it was a sign-in link.
  bool handleLink(Uri uri) {
    final link = codeFromDeepLink(uri);
    if (link == null) return false;
    if (link.code != null && link.code!.isNotEmpty) {
      finishSignIn(link.code!);
    } else {
      state = state.copyWith(error: 'Google sign-in was cancelled.');
    }
    return true;
  }

  /// "Continue with Google": opens the browser; the code comes back through `escanor://auth/login`.
  Future<void> signInWithGoogle() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final pkce = createPkcePair();
      Storage.instance.setSecret(_pkceKey, pkce.verifier);
      final r = await api.get(
        '/auth/oauth/google/authorize?platform=mobile&redirect_uri=${enc(mobileLoginRedirect)}'
        '&code_challenge=${enc(pkce.challenge)}&code_challenge_method=S256',
        auth: false,
      ) as Map<String, dynamic>;
      final url = Uri.parse(r['authorization_url'] as String);
      // An external browser: Google refuses sign-in inside embedded web views.
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      state = state.copyWith(error: errorText(e, 'Could not start sign-in.'));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Email sign-in, part one: remember a PKCE secret for this attempt and return its challenge.
  String beginEmailSignIn() {
    final pkce = createPkcePair();
    Storage.instance.setSecret(_pkceKey, pkce.verifier);
    return pkce.challenge;
  }

  /// For development builds only: the backend refuses this unless ENABLE_DEV_AUTH is set.
  Future<void> devLogin(String email) async {
    final t = await api.post('/auth/dev/login', {'email': email, 'name': email.split('@').first}, false) as Map<String, dynamic>;
    api.tokens.set(t['access_token'] as String, t['refresh_token'] as String, (t['expires_in'] as num?)?.toInt());
    await load();
  }

  Future<void> signOut() async {
    _takeVerifier();
    for (final hook in signOutHooks) {
      try {
        await hook();
      } catch (_) {}
    }
    clearCache();
    final refresh = api.tokens.refresh;
    api.tokens.clear();
    if (refresh != null) {
      try {
        await api.post('/auth/logout', {'refresh_token': refresh}, false);
      } catch (_) {}
    }
    state = const SessionState(status: SessionStatus.signedOut);
  }

  void sessionEnded() {
    clearCache();
    state = const SessionState(status: SessionStatus.signedOut);
  }

  Future<void> refreshUser() async {
    final me = await fetchMe();
    writeCache(_userCache.key, me.toJson());
    state = state.copyWith(user: me);
  }

  void setError(String? e) => state = e == null ? state.copyWith(clearError: true) : state.copyWith(error: e);
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
