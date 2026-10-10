/// Port of escanor-desktop packages/remote/src/phone/lan-pair.ts: the local-network rules and pairing without a code.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'failure.dart';
import 'secure.dart';

final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// Whether a host is somewhere on the person's own network (or this device). The phone talks plain http/ws to a computer on the
/// local network (every message is sealed with the device key, so nothing readable crosses the air), and ONLY there: an address
/// anywhere else is ignored, so a mistyped or malicious address can never make the app send anything in the clear across the
/// internet.
bool isLocalAddress(String addr) {
  final host = addr.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').replaceFirst(RegExp(r'[:/].*$'), '').toLowerCase();
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final m = _ipv4.firstMatch(host);
  if (m == null) return false;
  final n = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (n.any((x) => x > 255)) return false;
  final a = n[0], b = n[1];
  return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254) || (a == 100 && b >= 64 && b <= 127);
}

/// Stop waiting (the person left the screen, or pressed Cancel).
class CancelToken {
  bool _cancelled = false;
  final _done = Completer<void>();
  bool get cancelled => _cancelled;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _done.complete();
  }
}

class LanAskOptions {
  const LanAskOptions({this.client, this.onConfirm, this.pollMs, this.cancel, this.now, this.sleep});
  final http.Client? client;

  /// Called once, as soon as the computer has answered, with the number to compare with the one on its screen.
  final void Function(String confirm)? onConfirm;
  final int? pollMs;
  final CancelToken? cancel;
  final int Function()? now;
  final Future<void> Function(Duration d)? sleep;
}

class LanAskResult {
  LanAskResult({required this.deviceId, required this.key, this.machineName});
  final String deviceId;
  final Uint8List key;

  /// What the computer calls itself.
  final String? machineName;
}

Future<T> withTimeout<T>(Future<T> f, Duration d, String what) => f.timeout(d, onTimeout: () => throw ComputerError('$what timed out'));

/// The `error` the computer put in a refusal, or [fallback].
String errorOfBody(String body, String fallback) {
  try {
    final j = jsonDecode(body);
    if (j is Map && j['error'] is String) return j['error'] as String;
  } catch (_) {}
  return fallback;
}

/// The phone's half of pairing without a code. It needs only the computer's address: it asks, shows a confirmation number, and
/// waits for the person to approve on the computer. See [approvalSecrets] for why the number matters.
Future<LanAskResult> phoneAskLan(String base, String deviceName, [LanAskOptions o = const LanAskOptions()]) async {
  final client = o.client ?? http.Client();
  final sleep = o.sleep ?? (Duration d) => Future<void>.delayed(d);
  final now = o.now ?? () => DateTime.now().millisecondsSinceEpoch;
  Future<http.Response> call(String path, {String? body}) {
    final uri = Uri.parse('$base$path');
    final f = body == null ? client.get(uri) : client.post(uri, body: body);
    final cancelled = o.cancel?.whenCancelled.then<http.Response>((_) => throw const ComputerError('Pairing was cancelled.'));
    return withTimeout(cancelled == null ? f : Future.any([f, cancelled]), const Duration(seconds: 5), 'The computer');
  }

  try {
    final mine = ecdhGenerate();
    final res = await call(
      '/pair/ask',
      body: jsonEncode({
        'v': 1,
        'device': {'name': deviceName},
        'pub': B64u.encode(mine.pub),
      }),
    );
    if (res.statusCode == 404) {
      throw const ComputerError('This computer does not allow pairing without a code. Update Escanor Desktop, or pair with the code instead.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw ComputerError(errorOfBody(res.body, 'The computer refused (${res.statusCode}).'));
    final started = jsonDecode(res.body) as Map<String, dynamic>;
    final machinePub = B64u.decode('${started['pub']}');
    final secrets = approvalSecrets(ecdhShared(mine.priv, machinePub), mine.pub, machinePub);
    o.onConfirm?.call(secrets.confirm);

    final ttl = started['ttlMs'] is num ? (started['ttlMs'] as num).toInt() : 110000;
    final until = now() + max(5000, ttl) + 5000;
    while (now() < until) {
      if (o.cancel?.cancelled == true) throw const ComputerError('Pairing was cancelled.');
      final wait = sleep(Duration(milliseconds: o.pollMs ?? 1000));
      await (o.cancel == null ? wait : Future.any([wait, o.cancel!.whenCancelled]));
      if (o.cancel?.cancelled == true) throw const ComputerError('Pairing was cancelled.');
      final poll = await call('/pair/ask/${Uri.encodeComponent('${started['id']}')}');
      if (poll.statusCode < 200 || poll.statusCode >= 300) throw ComputerError(errorOfBody(poll.body, 'The computer lost track of this request. Try again.'));
      final st = jsonDecode(poll.body) as Map<String, dynamic>;
      if (st['status'] == 'denied') throw const ComputerError('The computer said no.');
      if (st['status'] == 'expired') throw const ComputerError('Nobody answered on the computer in time. Try again.');
      if (st['status'] == 'approved' && st['deviceId'] is String && st['sealedKey'] is String) {
        final deviceId = st['deviceId'] as String;
        final machine = st['machine'];
        final name = machine is Map && machine['name'] != null && '${machine['name']}'.isNotEmpty ? '${machine['name']}' : null;
        return LanAskResult(deviceId: deviceId, key: open(secrets.key, st['sealedKey'] as String, 'pair:$deviceId'), machineName: name);
      }
    }
    throw const ComputerError('Nobody answered on the computer in time. Try again.');
  } finally {
    if (o.client == null) client.close();
  }
}
