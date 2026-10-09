/// Rules for a hub's address (api.ts, EscanorConnect.tsx). No Flutter here, so it is tested on its own.
library;

/// In the phone app a hub must be https: its token and every message cross the internet, and the app also talks plain
/// http to a computer on the local network, so this is what keeps the two apart. Null when the address is fine (or empty).
String? hubUrlProblem(String url) {
  if (url.trim().isEmpty) return null;
  return RegExp(r'^https://', caseSensitive: false).hasMatch(url.trim())
      ? null
      : 'A hub must start with https://. Put it behind TLS (a reverse proxy, a tunnel or the Cloudflare Worker hub).';
}

/// The address as it is stored: trimmed, no trailing slashes.
String cleanHubUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

/// The hub's push channel: the same host over wss. Only ever built from an https address.
Uri socketUrl(String hub) {
  final clean = cleanHubUrl(hub);
  if (hubUrlProblem(clean) != null || clean.isEmpty) throw ArgumentError('A hub must start with https://');
  return Uri.parse('${clean.replaceFirst(RegExp(r'^https', caseSensitive: false), 'wss')}/ws');
}

/// The subprotocols the hub expects: its protocol name, then the credential (kept out of the URL, which proxies log).
List<String> socketProtocols(String token) => ['escanor.hub.v1', 'escanor.auth.$token'];

/// Escanor's servers dial the hub, so an address that only works on this machine or its LAN cannot work.
bool isPrivateAddress(String url) {
  final Uri u;
  try {
    u = Uri.parse(url);
  } catch (_) {
    return false;
  }
  final host = u.host.toLowerCase();
  if (host.isEmpty) return false;
  return host == 'localhost' ||
      host.endsWith('.local') ||
      RegExp(r'^127\.').hasMatch(host) ||
      RegExp(r'^10\.').hasMatch(host) ||
      RegExp(r'^192\.168\.').hasMatch(host) ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host) ||
      RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(host) ||
      host == '::1' ||
      host == '[::1]';
}

/// Delay before the next reconnect attempt: 2s, 4s, 8s, 16s, then every 30s.
Duration reconnectDelay(int attempt) {
  final secs = 2 << (attempt.clamp(0, 4));
  return Duration(seconds: secs > 30 ? 30 : secs);
}
