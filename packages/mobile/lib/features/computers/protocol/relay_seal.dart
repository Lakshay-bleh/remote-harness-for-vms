/// Port of escanor-desktop packages/remote/src/relay-seal.ts. Sealing for the cloud relay: the phone queues a command in the
/// Escanor backend whose only content is a sealed blob, and the computer answers with another. The backend stores and forwards
/// ciphertext; it cannot read, alter or forge a message.
library;

import 'failure.dart';
import 'protocol.dart';
import 'secure.dart';

String _aad(String deviceId, String dir) => 'relay:$deviceId:$dir';

/// Seal one request. Returns its id (the reply must carry the same) and the sealed blob.
({String id, String sealed}) sealRelayRequest(String deviceId, List<int> deviceKey, Msg m, {int? now}) {
  final id = B64u.encode(randomBytes(12));
  final ts = now ?? DateTime.now().millisecondsSinceEpoch;
  return (id: id, sealed: sealJson(relayKey(deviceKey), {'id': id, 'ts': ts, 'm': m}, _aad(deviceId, 'req')));
}

/// The computer's half (used by tests to play the computer).
Map<String, dynamic> openRelayRequest(String deviceId, List<int> deviceKey, String sealed) =>
    Map<String, dynamic>.from(openJson(relayKey(deviceKey), sealed, _aad(deviceId, 'req')) as Map);

/// The computer's half (used by tests to play the computer). [res] is `{id, ts, replies}`.
String sealRelayResponse(String deviceId, List<int> deviceKey, Map<String, dynamic> res, {List<int>? iv}) =>
    sealJson(relayKey(deviceKey), res, _aad(deviceId, 'res'), iv);

/// Open the computer's answer, check it is the answer to [expectId] and is recent, and return its messages.
List<Msg> openRelayResponse(String deviceId, List<int> deviceKey, String sealed, String expectId, {int? now}) {
  final r = openJson(relayKey(deviceKey), sealed, _aad(deviceId, 'res'));
  if (r is! Map) throw const RelayFailure('That reply could not be read.');
  if (r['id'] != expectId) throw const RelayFailure('That reply belongs to a different request.');
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  final ts = r['ts'];
  if (ts is! num || (t - ts).abs() > maxSkewMs) throw const RelayFailure('That reply is too old.');
  final replies = r['replies'];
  return replies is List
      ? [
          for (final m in replies)
            if (m is Map) Map<String, dynamic>.from(m),
        ]
      : const [];
}

class RelayFailure extends ComputerError {
  const RelayFailure(super.message);
}
