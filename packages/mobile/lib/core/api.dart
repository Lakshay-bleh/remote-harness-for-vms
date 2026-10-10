import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'storage.dart';

/// The Escanor backend, signed in. Feature areas add their own endpoints as extensions on [Api]
/// (see `features/*/..._api.dart`); this file owns tokens, renewal and errors.

class SessionEnded implements Exception {
  @override
  String toString() => 'Your Escanor session ended. Please sign in again.';
}

class ApiError implements Exception {
  ApiError(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// The text to show for any error thrown by the API or elsewhere.
String errorText(Object e, [String fallback = 'Something went wrong.']) {
  if (e is ApiError) return e.message;
  if (e is SessionEnded) return e.toString();
  if (e is StateError) return e.message;
  final s = e.toString();
  if (s.startsWith('Exception: ')) return s.substring(11);
  return s.isEmpty ? fallback : s;
}

const _access = 'escanor_access';
const _refresh = 'escanor_refresh';
const _expires = 'escanor_access_expires';

/// Renew the access token this long before it runs out.
const renewEarly = Duration(seconds: 90);

/// What the server gives an access token when it does not say (15 minutes).
const defaultAccessSeconds = 900;

class Tokens {
  Tokens(this._storage);
  final Storage _storage;

  String? get access => _storage.secret(_access);
  String? get refresh => _storage.secret(_refresh);

  /// When the access token stops working (ms since epoch), or 0 when unknown.
  int get expiresAt => int.tryParse(_storage.secret(_expires) ?? '') ?? 0;

  void set(String access, String refresh, [int? expiresInSeconds]) {
    _storage.setSecret(_access, access);
    _storage.setSecret(_refresh, refresh);
    final secs = (expiresInSeconds == null || expiresInSeconds <= 0) ? defaultAccessSeconds : expiresInSeconds;
    _storage.setSecret(_expires, '${DateTime.now().millisecondsSinceEpoch + secs * 1000}');
  }

  void clear() {
    _storage.setSecret(_access, null);
    _storage.setSecret(_refresh, null);
    _storage.setSecret(_expires, null);
  }

  bool get hasSession => (refresh ?? '').isNotEmpty || (access ?? '').isNotEmpty;
}

/// Is it time to get a new access token before asking for anything?
bool accessIsStale(int expiresAt, [int? now]) {
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  return expiresAt > 0 && t >= expiresAt - renewEarly.inMilliseconds;
}

/// Online now, or heard from within [window] (default ten minutes).
bool isRecentlySeen(String status, String? lastHeartbeat, {DateTime? now, Duration window = const Duration(minutes: 10)}) {
  if (status == 'online') return true;
  final t = lastHeartbeat == null ? null : DateTime.tryParse(lastHeartbeat);
  if (t == null) return false;
  final d = (now ?? DateTime.now()).difference(t);
  return !d.isNegative && d < window;
}

/// The backend's error text, whatever shape it came in.
String messageOf(Object? body, String fallback) {
  if (body is Map) {
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map && (detail.first as Map)['msg'] != null) {
      return '${(detail.first as Map)['msg']}';
    }
  }
  return fallback;
}

enum RefreshResult { ok, rejected, unavailable }

/// Only a refusal of the refresh token itself ends a session; a busy or unreachable server never signs anyone out.
RefreshResult refreshOutcome(int status) =>
    status == 400 || status == 401 || status == 403 ? RefreshResult.rejected : RefreshResult.unavailable;

class Api {
  Api({http.Client? client, Tokens? tokens, String? base})
      : _http = client ?? http.Client(),
        tokens = tokens ?? Tokens(Storage.instance),
        _base = base; // ignore: prefer_initializing_formals

  final http.Client _http;
  final Tokens tokens;
  final String? _base;

  String get base => _base ?? escanorApiBase();

  /// Called when a request finds the session over (the app goes back to sign-in).
  void Function()? onSessionEnded;

  Future<RefreshResult>? _refreshing;

  /// One refresh at a time, however many requests found the token expired together.
  Future<RefreshResult> refreshTokens() {
    return _refreshing ??= () async {
      try {
        final refresh = tokens.refresh;
        if (refresh == null || refresh.isEmpty) return RefreshResult.rejected;
        try {
          final res = await _http.post(Uri.parse('$base/auth/refresh'),
              headers: {'content-type': 'application/json'}, body: jsonEncode({'refresh_token': refresh}));
          if (res.statusCode < 200 || res.statusCode >= 300) return refreshOutcome(res.statusCode);
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          tokens.set(body['access_token'] as String, (body['refresh_token'] as String?) ?? refresh,
              (body['expires_in'] as num?)?.toInt());
          return RefreshResult.ok;
        } catch (_) {
          return RefreshResult.unavailable; // offline is not "signed out"
        }
      } finally {
        _refreshing = null;
      }
    }();
  }

  Never _ended() {
    tokens.clear();
    onSessionEnded?.call();
    throw SessionEnded();
  }

  /// Send a request. [body] is JSON-encoded unless it is already a String. Returns decoded JSON (or null for 204).
  Future<dynamic> request(String method, String path,
      {Object? body, bool auth = true, Map<String, String>? headers, Duration? timeout}) async {
    String? used;
    Future<http.Response> send() {
      used = auth ? tokens.access : null;
      final req = http.Request(method, Uri.parse('$base$path'));
      req.headers['content-type'] = 'application/json';
      if (used != null) req.headers['authorization'] = 'Bearer $used';
      if (headers != null) req.headers.addAll(headers);
      if (body != null) req.body = body is String ? body : jsonEncode(body);
      final f = _http.send(req).then(http.Response.fromStream);
      return timeout == null ? f : f.timeout(timeout);
    }

    if (auth && accessIsStale(tokens.expiresAt)) {
      if (await refreshTokens() == RefreshResult.rejected) _ended();
    }

    http.Response res;
    try {
      res = await send();
    } on TimeoutException {
      throw ApiError('Escanor took too long to answer. Try again.', 0);
    } catch (_) {
      throw ApiError('Could not reach Escanor. Check your connection.', 0);
    }
    for (var attempt = 0; res.statusCode == 401 && auth && attempt < 2; attempt++) {
      final now = tokens.access;
      if (now != null && now != used) {
        res = await send(); // another request already renewed it
        continue;
      }
      final r = await refreshTokens();
      if (r == RefreshResult.unavailable) {
        throw ApiError('Could not reach Escanor to keep you signed in. Try again in a moment.', 0);
      }
      if (r == RefreshResult.rejected) _ended();
      res = await send();
    }
    if (res.statusCode == 401 && auth) {
      throw ApiError('Escanor could not confirm it is you for that. Try again in a moment.', 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      Object? parsed;
      try {
        parsed = jsonDecode(res.body);
      } catch (_) {}
      throw ApiError(messageOf(parsed, 'Something went wrong (${res.statusCode}).'), res.statusCode);
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> get(String path, {bool auth = true}) => request('GET', path, auth: auth);
  Future<dynamic> post(String path, [Object? body, bool auth = true]) => request('POST', path, body: body, auth: auth);
  Future<dynamic> patch(String path, Object? body) => request('PATCH', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) => request('DELETE', path, body: body);

  /// A raw GET outside the API base (the health check), with no auth.
  Future<http.Response> rawGet(Uri uri) => _http.get(uri);
}

/// Percent-encode one path segment or query value.
String enc(String s) => Uri.encodeComponent(s);

/// The one API the app uses. Replaced in tests.
late Api api;
