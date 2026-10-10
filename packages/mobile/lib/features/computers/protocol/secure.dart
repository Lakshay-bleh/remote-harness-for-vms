/// Port of escanor-desktop packages/remote/src/secure.ts (the phone <-> computer crypto). Byte for byte the same as the
/// TypeScript (WebCrypto) version: the computer opens what this seals and the other way round. Pure Dart (pointycastle +
/// crypto), no Flutter, so it is tested directly against vectors produced by the TypeScript code.
///
///   pairing secret S ──HKDF──▶ pairing key ──seals──▶ device key K   (S travels only in the QR code)
///   K ──HMAC──▶ mutual proofs ──HKDF──▶ session key ──AES-GCM──▶ every message (LAN)
///   K ──HKDF──▶ relay key ──AES-GCM──▶ sealed commands through the Escanor cloud (it sees ciphertext only)
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart' as pc;

import 'failure.dart';

// ---- base64url without padding ---------------------------------------------------------------------------------------

abstract final class B64u {
  static String encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List decode(String text) {
    final pad = '=' * ((4 - text.length % 4) % 4);
    // atob in the TypeScript accepts either alphabet once normalised; do the same.
    return base64Url.decode(text.replaceAll('+', '-').replaceAll('/', '_') + pad);
  }
}

final Random _secure = Random.secure();

Uint8List _secureRandomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _secure.nextInt(256)));

/// Where random bytes come from. Always the platform's secure generator; replaced only by tests that need fixed IVs.
Uint8List Function(int n) randomBytes = _secureRandomBytes;

/// Constant-time equality for equal-length byte strings.
bool timingSafeEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

/// HMAC-SHA256 over the parts, each followed by a 0 byte, so ("ab","c") and ("a","bc") never collide.
/// A part is a String (UTF-8) or bytes.
Uint8List hmac(List<int> key, List<Object> parts) {
  final total = BytesBuilder(copy: false);
  for (final p in parts) {
    total.add(p is String ? _utf8(p) : p as List<int>);
    total.addByte(0);
  }
  return Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(total.toBytes()).bytes);
}

Uint8List _hmacRaw(List<int> key, List<int> data) => Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

/// HKDF-SHA256 to 32 bytes. [salt] is a String (UTF-8) or bytes.
Uint8List hkdf(List<int> secret, Object salt, String info) {
  final s = salt is String ? _utf8(salt) : salt as List<int>;
  final prk = _hmacRaw(s, secret); // extract
  return _hmacRaw(
    prk,
    _concat([
      _utf8(info),
      [1],
    ]),
  ); // expand: one block is exactly 32 bytes
}

pc.GCMBlockCipher _gcm(bool encrypt, List<int> key, List<int> iv, List<int> aad) {
  final g = pc.GCMBlockCipher(pc.AESEngine());
  g.init(encrypt, pc.AEADParameters(pc.KeyParameter(Uint8List.fromList(key)), 128, Uint8List.fromList(iv), Uint8List.fromList(aad)));
  return g;
}

/// AES-256-GCM with a fresh random IV. Output: IV (12) || ciphertext+tag, base64url. [aad] binds the message to its context.
/// [plaintext] is a String (UTF-8) or bytes. [iv] is for tests only.
String seal(List<int> key, Object plaintext, [String aad = '', List<int>? iv]) {
  final nonce = iv ?? randomBytes(12);
  final data = plaintext is String ? _utf8(plaintext) : Uint8List.fromList(plaintext as List<int>);
  final ct = _gcm(true, key, nonce, _utf8(aad)).process(data);
  return B64u.encode(_concat([nonce, ct]));
}

/// The opposite of [seal]. Throws [CryptoFailure] when the message was changed, is for another context, or is not ours.
Uint8List open(List<int> key, String sealed, [String aad = '']) {
  Uint8List raw;
  try {
    raw = B64u.decode(sealed);
  } catch (_) {
    throw const CryptoFailure('message could not be authenticated');
  }
  if (raw.length < 12 + 16) throw const CryptoFailure('message too short');
  try {
    return _gcm(false, key, raw.sublist(0, 12), _utf8(aad)).process(raw.sublist(12));
  } catch (_) {
    throw const CryptoFailure('message could not be authenticated');
  }
}

String sealJson(List<int> key, Object? value, [String aad = '', List<int>? iv]) => seal(key, jsonEncode(value), aad, iv);
Object? openJson(List<int> key, String sealed, [String aad = '']) => jsonDecode(utf8.decode(open(key, sealed, aad)));

class CryptoFailure extends ComputerError {
  const CryptoFailure(super.message);
}

// ---- Pairing ---------------------------------------------------------------------------------------------------------

/// A pairing secret as shown to the person: 20 random bytes in base32, grouped (`ABCD-EFGH-…`). 160 bits: not guessable.
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

({Uint8List bytes, String code}) newPairingSecret() {
  final bytes = randomBytes(20);
  return (bytes: bytes, code: formatCode(bytes));
}

String formatCode(List<int> bytes) {
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    value = ((value << 8) | b) & 0xFFFFFFFF;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  final s = out.toString();
  final groups = <String>[];
  for (var i = 0; i < s.length; i += 4) {
    groups.add(s.substring(i, min(i + 4, s.length)));
  }
  return groups.join('-');
}

final _codeShape = RegExp(r'^[A-Z2-7]{32}$');

/// Parse a typed or scanned code back to bytes. Tolerates case, spaces and dashes; rejects anything else.
Uint8List parseCode(String code) {
  final clean = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!_codeShape.hasMatch(clean)) throw const ComputerError('That pairing code is not valid.');
  final out = <int>[];
  var bits = 0;
  var value = 0;
  for (final ch in clean.split('')) {
    value = ((value << 5) | _alphabet.indexOf(ch)) & 0xFFFFFFFF;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

Uint8List pairingKey(List<int> secret) => hkdf(secret, 'escanor-pair-v1', 'pairing key');
Uint8List pairProof(List<int> secret, String nonce, String deviceName) => hmac(secret, ['pair', nonce, deviceName]);

/// A short tag derived from the pairing secret, sent with a cloud pairing so that only the computer showing this code answers.
/// 32 bits of a one-way function of the secret: it does not give the secret away.
String pairSelector(List<int> secret) => B64u.encode(hmac(secret, ['sel']).sublist(0, 4));
Uint8List relayKey(List<int> deviceKey) => hkdf(deviceKey, 'escanor-relay-v1', 'relay key');

// ---- LAN session handshake -------------------------------------------------------------------------------------------

Uint8List serverProof(List<int> k, String nonceC, String nonceS) => hmac(k, ['srv', nonceC, nonceS]);
Uint8List clientProof(List<int> k, String nonceC, String nonceS) => hmac(k, ['cli', nonceS, nonceC]);
Uint8List sessionKey(List<int> k, String nonceC, String nonceS) => hkdf(k, _utf8('$nonceC.$nonceS'), 'session key');

// ---- Pairing by approval (same network, no code) ---------------------------------------------------------------------
//
// The phone and the computer each make a throwaway P-256 key and swap the public halves. Both derive the same secret: from it, a
// key that seals the new device key for the phone, and a six-digit confirmation number shown on BOTH screens. Someone in between
// would end up with a different secret with each side, so the numbers would not match.

final pc.ECDomainParameters _p256 = pc.ECCurve_secp256r1();

class EcdhKeys {
  EcdhKeys(this.priv, this.pub);
  final pc.ECPrivateKey priv;

  /// 65 bytes, uncompressed point.
  final Uint8List pub;
}

pc.SecureRandom _fortuna() {
  final r = pc.FortunaRandom();
  r.seed(pc.KeyParameter(randomBytes(32)));
  return r;
}

EcdhKeys ecdhGenerate() {
  final gen = pc.ECKeyGenerator()..init(pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(_p256), _fortuna()));
  final pair = gen.generateKeyPair();
  return EcdhKeys(pair.privateKey, Uint8List.fromList(pair.publicKey.Q!.getEncoded(false)));
}

/// A private key from its 32-byte scalar (tests: keys made by the TypeScript side).
EcdhKeys ecdhFromPrivate(List<int> d) {
  final scalar = _toBigInt(d);
  final q = (_p256.G * scalar)!;
  return EcdhKeys(pc.ECPrivateKey(scalar, _p256), Uint8List.fromList(q.getEncoded(false)));
}

/// True for what a P-256 public key looks like on the wire.
bool isEcdhPublicKey(List<int> b) => b.length == 65 && b[0] == 4;

/// The shared secret: the x coordinate, 32 bytes big-endian (what WebCrypto's deriveBits(256) returns).
Uint8List ecdhShared(pc.ECPrivateKey priv, List<int> peerPub) {
  if (!isEcdhPublicKey(peerPub)) throw const CryptoFailure('That is not a valid public key.');
  final x = _toBigInt(peerPub.sublist(1, 33));
  final y = _toBigInt(peerPub.sublist(33, 65));
  final curve = _p256.curve as fp.ECCurve;
  final p = curve.q!;
  final a = curve.a!.toBigInteger()!;
  final b = curve.b!.toBigInteger()!;
  // WebCrypto refuses a point that is not on the curve; so does this (an invalid-curve attack would otherwise leak the key).
  if (x >= p || y >= p || (y * y - (x * x * x + a * x + b)) % p != BigInt.zero) {
    throw const CryptoFailure('That is not a valid public key.');
  }
  final point = curve.createPoint(x, y);
  final agreement = pc.ECDHBasicAgreement()..init(priv);
  final z = agreement.calculateAgreement(pc.ECPublicKey(point, _p256));
  return _fromBigInt(z, 32);
}

/// The sealing key and the confirmation number ("482 913") for one approval.
({Uint8List key, String confirm}) approvalSecrets(List<int> shared, List<int> phonePub, List<int> machinePub) {
  final salt = _concat([phonePub, machinePub]);
  final key = hkdf(shared, salt, 'escanor-approve-v1 key');
  final bits = hkdf(shared, salt, 'escanor-approve-v1 confirm');
  final n = ((bits[0] << 24) | (bits[1] << 16) | (bits[2] << 8) | bits[3]) & 0xFFFFFFFF;
  final digits = (n % 1000000).toString().padLeft(6, '0');
  return (key: key, confirm: '${digits.substring(0, 3)} ${digits.substring(3)}');
}

BigInt _toBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List _fromBigInt(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}
