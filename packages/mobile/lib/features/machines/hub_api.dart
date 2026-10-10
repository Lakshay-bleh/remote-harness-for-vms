import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/storage.dart';
import 'hub_url.dart';
import 'protocol.dart';
import 'session_search.dart';

/// Where this phone keeps its hub login: the address (an ordinary setting) and the token (a secret, in the
/// Keychain / Keystore). A flag marks credentials that came from Escanor's hosted hub, so signing out of
/// Escanor takes them away again (managed.ts).
class HubCredentials {
  const HubCredentials();

  static const tokenKey = 'rh_token';
  static const hubUrlKey = 'rh_hub_url';
  static const managedKey = 'rh_managed';

  Storage get _s => Storage.instance;

  String? get token {
    final t = _s.secret(tokenKey);
    return t == null || t.isEmpty ? null : t;
  }

  set token(String? value) => _s.setSecret(tokenKey, value == null || value.isEmpty ? null : value);

  /// The saved address. An old plain-http address saved before the https rule is ignored, not used.
  String get hubUrl {
    final url = cleanHubUrl(_s.getString(hubUrlKey) ?? '');
    return hubUrlProblem(url) != null ? '' : url;
  }

  /// Throws the reason when the address is not https.
  set hubUrl(String url) {
    final clean = cleanHubUrl(url);
    final problem = hubUrlProblem(clean);
    if (problem != null) throw StateError(problem);
    _s.setString(hubUrlKey, clean.isEmpty ? null : clean);
  }

  bool get managed => _s.getString(managedKey) == '1';
  set managed(bool on) => _s.setString(managedKey, on ? '1' : null);

  /// Signed in to a hub this phone can reach.
  bool get signedIn => token != null && hubUrl.isNotEmpty;
}

class HubError implements Exception {
  HubError(this.message, [this.status = 0, this.unreachable = false]);
  final String message;
  final int status;

  /// No answer came (timeout, no network): asking again may work.
  final bool unreachable;
  @override
  String toString() => message;
}

/// The hub's REST API (api.ts). Every answer is checked against the login it was asked with: if the person signed
/// out or switched hubs meanwhile, the answer is thrown away rather than shown to the next person.
class HubApi {
  HubApi({http.Client? client, this.credentials = const HubCredentials()})
      : _http = client ?? http.Client(),
        _injected = client != null;

  http.Client _http;

  /// A client handed in (tests) is never swapped for a fresh one.
  final bool _injected;
  final HubCredentials credentials;

  /// The hosted hub refused its token (rotated elsewhere): ask Escanor for the current one.
  void Function()? onManagedUnauthorized;

  /// A self-hosted hub refused the token: back to the hub sign-in.
  void Function()? onSignedOut;

  static const _timeout = Duration(seconds: 30);

  /// Answering a prompt, stopping a run or switching mode are tiny requests: if one has not come back in this long its
  /// connection is stuck (a phone that changed network keeps a dead one around), so it is tried again on a new one.
  static const controlTimeout = Duration(seconds: 8);
  static const controlAttempts = 3;

  /// Forget the pooled connections, which may be dead after a network change or a long time in the background.
  void resetConnections() {
    if (_injected) return;
    final old = _http;
    _http = http.Client();
    try {
      old.close();
    } catch (_) {}
  }

  Future<dynamic> request(String path,
      {String method = 'GET', Object? body, bool auth = true, Duration? timeout, int attempts = 1, bool Function(HubError)? okIf}) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _request(path, method: method, body: body, auth: auth, timeout: timeout ?? _timeout);
      } on HubError catch (e) {
        if (okIf != null && okIf(e)) return null;
        // Only a request that never got an answer is tried again; a refusal from the hub is final.
        if (!e.unreachable || attempt >= attempts) rethrow;
        resetConnections();
      }
    }
  }

  Future<dynamic> _request(String path, {required String method, Object? body, required bool auth, required Duration timeout}) async {
    final requestToken = auth ? credentials.token : null;
    final requestHub = credentials.hubUrl;
    void assertCurrentSession() {
      if ((auth ? credentials.token : null) != requestToken || credentials.hubUrl != requestHub) {
        throw HubError('Session changed; response discarded');
      }
    }

    if (requestHub.isEmpty) throw HubError('Hub URL must start with https://');
    final req = http.Request(method, Uri.parse('$requestHub/api$path'));
    req.headers['content-type'] = 'application/json';
    if (requestToken != null) req.headers['authorization'] = 'Bearer $requestToken';
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await _http.send(req).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw HubError('Your hub took too long to answer. Try again.', 0, true);
    } catch (_) {
      throw HubError('Could not reach your hub. Check your connection.', 0, true);
    }
    assertCurrentSession();
    if (res.statusCode == 401 && auth) {
      // Hosted hubs refresh through Escanor; a self-hosted one sends the person back to its sign-in.
      if (credentials.managed) {
        onManagedUnauthorized?.call();
        throw HubError('Reconnecting to your hub…', 401);
      }
      credentials.token = null;
      onSignedOut?.call();
      throw HubError('Unauthorized', 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? message;
      try {
        final b = jsonDecode(utf8.decode(res.bodyBytes));
        if (b is Map && b['error'] is String && (b['error'] as String).isNotEmpty) message = b['error'] as String;
      } catch (_) {
        message = res.reasonPhrase?.isNotEmpty == true ? res.reasonPhrase : null; // not JSON: the status line
      }
      assertCurrentSession();
      throw HubError(message ?? 'Request failed: ${res.statusCode}', res.statusCode);
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    final result = jsonDecode(utf8.decode(res.bodyBytes));
    assertCurrentSession();
    return result;
  }

  Future<dynamic> _post(String path, [Object? body]) => request(path, method: 'POST', body: body);

  String _e(String s) => Uri.encodeComponent(s);

  Future<String> login(String password) async {
    final r = await request('/login', method: 'POST', body: {'password': password}, auth: false);
    final token = r is Map ? r['token'] : null;
    if (token is! String || token.isEmpty) throw HubError('Login failed');
    return token;
  }

  Future<void> logout() => _post('/logout');

  Future<List<ApiTokenDto>> listApiTokens() async => ApiTokenDto.listFrom(await request('/tokens'));

  /// scope 'mcp' limits the token to managing MCP servers (what Escanor needs); it cannot start sessions or answer
  /// permission cards.
  Future<ApiTokenDto> createApiToken(String label, {String scope = 'full'}) async {
    final t = ApiTokenDto.tryParse(await _post('/tokens', {'label': label, 'scope': scope}));
    if (t == null) throw HubError('Could not create a token');
    return t;
  }

  Future<void> deleteApiToken(String id) => request('/tokens/${_e(id)}', method: 'DELETE');

  Future<List<VmDto>> listVms() async => VmDto.listFrom(await request('/vms'));

  Future<McpOverview> getMcpOverview() async => McpOverview.fromJson(await request('/mcp-servers'));

  Future<List<SessionDto>> listSessions(String vmId) async => SessionDto.listFrom(await request('/vms/${_e(vmId)}/sessions'));

  /// Chats on this machine whose title or messages match [query], best first. A hub from before search answers 404.
  Future<List<SessionSearchHit>> searchSessions(String vmId, String query, {int limit = 20}) async =>
      SessionSearchHit.listFrom(await request('/vms/${_e(vmId)}/sessions/search?q=${_e(query)}&limit=$limit', timeout: controlTimeout));

  Future<List<String>> listProjects(String vmId) async {
    final r = await request('/vms/${_e(vmId)}/projects');
    return r is List ? [for (final p in r) if (p is String) p] : const [];
  }

  Future<List<MessageDto>> listMessages(String vmId, String sessionId) async =>
      MessageDto.listFrom(await request('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/messages'));

  Future<String> createSession(String vmId, NewSessionInput input) async {
    final r = await _post('/vms/${_e(vmId)}/sessions', {
      'text': input.text,
      if (input.images != null) 'images': [for (final i in input.images!) i.toJson()],
      'cwd': ?input.cwd,
      'accountId': ?input.accountId,
    });
    final tempId = r is Map ? r['tempId'] : null;
    if (!isIdString(tempId)) throw HubError('The hub did not start the chat.');
    return tempId as String;
  }

  Future<void> sendMessage(String vmId, String sessionId, UserInput input) => _post('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/messages', {
        'text': input.text,
        if (input.images != null) 'images': [for (final i in input.images!) i.toJson()],
      });

  Future<void> _control(String path, [Object? body, bool Function(HubError)? okIf]) =>
      request(path, method: 'POST', body: body, timeout: controlTimeout, attempts: controlAttempts, okIf: okIf);

  Future<void> interrupt(String vmId, String sessionId) => _control('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/interrupt', {});

  Future<void> setPermissionMode(String vmId, String sessionId, String mode) =>
      _control('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/permission-mode', {'mode': mode});

  Future<void> setModel(String vmId, String sessionId, String model) => _control('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/model', {'model': model});

  Future<void> setEffort(String vmId, String sessionId, String effort) =>
      _control('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/effort', {'effort': effort});

  /// Rename a chat on the hub. A hub that cannot answers 404/405 (see [HubStore.renameSession], which then keeps the name on the phone).
  Future<void> renameSession(String vmId, String sessionId, String title) =>
      request('/vms/${_e(vmId)}/sessions/${_e(sessionId)}', method: 'PATCH', body: {'title': title}, timeout: controlTimeout);

  Future<void> deleteSession(String vmId, String sessionId) =>
      request('/vms/${_e(vmId)}/sessions/${_e(sessionId)}', method: 'DELETE', timeout: controlTimeout);

  Future<void> renameVm(String vmId, String name) => request('/vms/${_e(vmId)}', method: 'PATCH', body: {'name': name}, timeout: controlTimeout);

  Future<void> deleteVm(String vmId) => request('/vms/${_e(vmId)}', method: 'DELETE', timeout: controlTimeout);

  /// An answer to a prompt that is already gone (answered on another device, or the run ended) is as good as delivered.
  Future<void> resolvePermission(String vmId, String sessionId, String requestId, String behavior) =>
      _control('/vms/${_e(vmId)}/sessions/${_e(sessionId)}/permission-response', {'requestId': requestId, 'behavior': behavior},
          (e) => e.status == 404 || e.status == 409 || e.status == 410);
}
