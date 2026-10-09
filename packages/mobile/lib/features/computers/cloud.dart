import 'dart:async';
import 'dart:math';

import '../../core/api.dart';
import 'protocol/client.dart';
import 'protocol/failure.dart';

/// Escanor Desktop through the Escanor backend: end-to-end encrypted commands for one of the person's own computers, answered when
/// it next polls. The backend only ever carries what the phone sealed.
extension ComputersApi on Api {
  /// Queue a command for a computer through the backend and wait for it to finish.
  Future<Map<String, dynamic>> runOnComputer(
    String agentId,
    String action,
    Map<String, dynamic> parameters, {
    Duration timeout = const Duration(seconds: 120),
    Future<void> Function(Duration d)? sleep,
  }) async {
    final wait = sleep ?? (Duration d) => Future<void>.delayed(d);
    var cmd = Map<String, dynamic>.from(
      await post('/agents/commands', {
        'agent_id': agentId,
        'plugin': 'desktop',
        'action': action,
        'parameters': parameters,
        'approve_immediately': true,
        'wait_for_result': true,
      }) as Map,
    );
    final until = DateTime.now().add(timeout);
    bool finished() => const {'succeeded', 'failed', 'cancelled'}.contains(cmd['status']);
    // Quick at first (the computer answers within a second or two when it is awake), then easier on the server.
    for (var n = 0; !finished() && DateTime.now().isBefore(until); n++) {
      await wait(Duration(milliseconds: min(1000, 350 + n * 150)));
      cmd = Map<String, dynamic>.from(await get('/agents/commands/${enc('${cmd['id']}')}') as Map);
    }
    if (cmd['status'] != 'succeeded') {
      throw ComputerError(
        cmd['status'] == 'failed'
            ? (cmd['error'] is String && (cmd['error'] as String).isNotEmpty ? cmd['error'] as String : 'The computer refused that.')
            : 'The computer did not answer. Is it on and online?',
      );
    }
    return cmd['result'] is Map ? Map<String, dynamic>.from(cmd['result'] as Map) : {};
  }

  /// One sealed blob to a computer and its sealed answer: the cloud route of [ComputerClient].
  Future<String> sendToComputer(String agentId, String deviceId, String sealed) async {
    final r = await runOnComputer(agentId, 'sealed', {'dev': deviceId, 'sealed': sealed});
    final s = r['sealed'];
    if (s == null || '$s'.isEmpty) throw const ComputerError('The computer did not answer. Is it on and online?');
    return '$s';
  }

  /// The computers of this account that run Escanor Desktop (a phone signed in to the same account can find them to pair).
  Future<List<DesktopEntry>> desktops() async {
    final r = await get('/agents');
    final agents = r is Map && r['agents'] is List ? r['agents'] as List : const [];
    // The server calls a computer online for 90 s after its last heartbeat, which is sent every 30 s: one late heartbeat (a busy or
    // briefly sleeping laptop) made a running computer look off. A heartbeat in the last ten minutes is good enough to try it.
    return [
      for (final a in agents)
        if (a is Map && a['health'] is Map && (a['health'] as Map)['app'] == 'escanor-desktop')
          DesktopEntry(
            id: '${a['id']}',
            name: '${a['name'] ?? 'My computer'}',
            online: isRecentlySeen('${a['runtime_status'] ?? ''}', a['last_heartbeat_at'] as String?),
          ),
    ];
  }

  Future<({String deviceId, String sealedKey})> pairWithDesktop(
    String agentId, {
    required String sel,
    required String nonce,
    required String proof,
    required String name,
  }) async {
    // a computer that is really there answers within seconds
    final r = await runOnComputer(agentId, 'pair', {'sel': sel, 'nonce': nonce, 'proof': proof, 'name': name}, timeout: const Duration(seconds: 45));
    if (r['deviceId'] is! String || r['sealedKey'] is! String) throw const ComputerError('The computer did not complete the pairing.');
    return (deviceId: r['deviceId'] as String, sealedKey: r['sealedKey'] as String);
  }
}

/// The signed-in app's own backend is how a phone finds the person's computers and reaches them from anywhere.
class ApiCloudDirectory implements CloudDirectory {
  ApiCloudDirectory([Api? using]) : _api = using;
  final Api? _api;
  Api get _a => _api ?? api;

  @override
  Future<List<DesktopEntry>> computers() => _a.desktops();

  @override
  Future<({String deviceId, String sealedKey})> pair(
    String agentId, {
    required String sel,
    required String nonce,
    required String proof,
    required String name,
  }) => _a.pairWithDesktop(agentId, sel: sel, nonce: nonce, proof: proof, name: name);
}

/// The cloud route for [ComputerClient], through the signed-in API.
RelayTransport apiRelay([Api? using]) =>
    ({required String agentId, required String deviceId, required String sealed}) => (using ?? api).sendToComputer(agentId, deviceId, sealed);
