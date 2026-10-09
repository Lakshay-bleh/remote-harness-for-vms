/// Port of escanor-desktop packages/remote/src/phone/redeem.ts.
library;

import 'dart:typed_data';

import 'secure.dart';

/// What the phone sends to redeem a pairing code.
class RedeemBody {
  const RedeemBody({required this.nonce, required this.proof, required this.deviceName});
  final String nonce;
  final String proof;
  final String deviceName;

  /// The body of `POST /pair` on the computer's local gateway.
  Map<String, dynamic> toJson() => {
    'v': 1,
    'nonce': nonce,
    'proof': proof,
    'device': {'name': deviceName},
  };
}

/// The phone's half: prove knowledge of the code, and unseal the device key it is given.
Future<({String deviceId, Uint8List key})> phoneRedeem(
  List<int> code,
  String deviceName,
  Future<({String deviceId, String sealedKey})> Function(RedeemBody body) post,
) async {
  final nonce = B64u.encode(randomBytes(16));
  final proof = B64u.encode(pairProof(code, nonce, deviceName));
  final r = await post(RedeemBody(nonce: nonce, proof: proof, deviceName: deviceName));
  return (deviceId: r.deviceId, key: open(pairingKey(code), r.sealedKey, 'pair:${r.deviceId}'));
}
