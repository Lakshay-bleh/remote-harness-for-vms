import '../../core/api.dart';
import 'actions.dart';
import 'device.dart';
import 'server_plan.dart';

({DateTime at, List<Map<String, String>> apps})? _cached;
const _fresh = Duration(minutes: 1);

/// This phone's apps for the server, listed at most once a minute (listing is the slow part).
Future<List<Map<String, String>>> _phoneApps(DevicePlugin? dev) async {
  if (dev == null) return const [];
  final c = _cached;
  if (c != null && DateTime.now().difference(c.at) < _fresh) return c.apps;
  try {
    final apps = appsForServer(await dev.listApps());
    _cached = (at: DateTime.now(), apps: apps);
    return apps;
  } catch (_) {
    return const [];
  }
}

/// Ask the server's voice brain about a sentence (POST /ai/voice/resolve). Null when signed out, offline, or anything goes wrong:
/// the caller carries on without it.
Future<ServerPlan?> resolveOnServer(String text, DevicePlugin? dev) async {
  if (!api.tokens.hasSession) return null;
  try {
    final body = {
      'text': text,
      'client': 'mobile',
      'device': {'platform': isIOS ? 'ios' : 'android', 'apps': await _phoneApps(dev)},
    };
    return ServerPlan.fromJson(await api.request('POST', '/ai/voice/resolve', body: body, timeout: const Duration(seconds: 40)));
  } catch (_) {
    return null;
  }
}
