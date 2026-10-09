import '../../core/api.dart';
import 'settings_logic.dart';

/// The endpoints Settings uses (the same ones the website uses).

/// Today's and this month's use of the assistant (`AssistantUsage`), raw JSON.
Future<Map<String, dynamic>> fetchUsage() async => Map<String, dynamic>.from(await api.get('/ai/usage') as Map);

Future<void> updateProfile(String name) => api.patch('/users/me', {'name': name});

Future<Map<String, dynamic>> fetchNotificationPrefs() async =>
    Map<String, dynamic>.from(await api.get('/users/me/notification-preferences') as Map);

Future<NotificationPrefs> setNotificationPrefs(Map<String, bool> patch) async =>
    NotificationPrefs.fromJson(Map<String, dynamic>.from(await api.patch('/users/me/notification-preferences', patch) as Map));

/// How long the backend takes to answer: the "is it me or the server" check. Needs no sign-in.
Future<({bool ok, int ms, int status})> ping() async {
  final sw = Stopwatch()..start();
  try {
    final res = await api.rawGet(healthUri(api.base)).timeout(const Duration(seconds: 15));
    return (ok: res.statusCode >= 200 && res.statusCode < 300, ms: sw.elapsedMilliseconds, status: res.statusCode);
  } catch (_) {
    return (ok: false, ms: sw.elapsedMilliseconds, status: 0);
  }
}

// -- other AI apps

Future<List<dynamic>> fetchMcpConnections() async => List<dynamic>.from(await api.get('/agent/mcp/connections') as List);

Future<McpInstall> createMcpInstall(String name) async =>
    McpInstall.fromJson(Map<String, dynamic>.from(await api.post('/agent/mcp/install', {'name': name}) as Map));

Future<void> renameMcp(String id, String name) => api.patch('/agent/mcp/connections/${enc(id)}', {'name': name});

/// A new key in place of this one: the old stops working at once.
Future<McpInstall> rotateMcp(String id) async =>
    McpInstall.fromJson(Map<String, dynamic>.from(await api.post('/agent/mcp/connections/${enc(id)}/rotate') as Map));

Future<void> revokeMcp(String id) => api.delete('/tokens/${enc(id)}');
