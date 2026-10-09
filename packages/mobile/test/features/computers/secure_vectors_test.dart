// Cross-implementation vectors: fixtures/vectors.json was produced by the TypeScript phone library (see interop/make_vectors.mts).
// The Dart port must produce exactly the same bytes, and open exactly what TypeScript sealed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:escanor/features/computers/protocol/relay_seal.dart';
import 'package:escanor/features/computers/protocol/secure.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hx(String h) => Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(File('test/features/computers/fixtures/vectors.json').readAsStringSync()) as Map<String, dynamic>;

  test('base64url matches, both ways', () {
    for (final e in v['b64u'] as List) {
      expect(B64u.encode(hx(e['hex'] as String)), e['b64u']);
      expect(toHex(B64u.decode(e['b64u'] as String)), e['hex']);
    }
  });

  test('pairing codes format and parse the same', () {
    final c = v['code'] as Map;
    expect(formatCode(hx(c['secretHex'] as String)), c['code']);
    expect(toHex(parseCode((c['code'] as String).toLowerCase().replaceAll('-', ' '))), c['parsedHex']);
    expect(() => parseCode('ABCD-EFGH'), throwsA(predicate((e) => '$e' == 'That pairing code is not valid.')));
  });

  test('HMAC with separators and HKDF match', () {
    for (final e in v['hmac'] as List) {
      expect(toHex(hmac(hx(e['keyHex'] as String), (e['parts'] as List).cast<String>())), e['outHex'], reason: '${e['parts']}');
    }
    for (final e in v['hkdf'] as List) {
      final salt = e['saltHex'] != null ? hx(e['saltHex'] as String) : e['salt'] as String;
      expect(toHex(hkdf(hx(e['secretHex'] as String), salt, e['info'] as String)), e['outHex']);
    }
  });

  test('every named key and proof matches', () {
    final d = v['derive'] as Map;
    final secret = hx(d['secretHex'] as String);
    final k = hx(d['deviceKeyHex'] as String);
    final nc = d['nonceC'] as String, ns = d['nonceS'] as String;
    expect(B64u.encode(k), d['deviceKeyB64u']);
    expect(toHex(pairingKey(secret)), d['pairingKeyHex']);
    expect(B64u.encode(pairProof(secret, d['pairNonce'] as String, d['deviceName'] as String)), d['pairProofB64u']);
    expect(pairSelector(secret), d['pairSelector']);
    expect(toHex(relayKey(k)), d['relayKeyHex']);
    expect(B64u.encode(serverProof(k, nc, ns)), d['serverProofB64u']);
    expect(B64u.encode(clientProof(k, nc, ns)), d['clientProofB64u']);
    expect(toHex(sessionKey(k, nc, ns)), d['sessionKeyHex']);
  });

  test('AES-GCM: the same IV gives the same sealed text, and TypeScript\'s opens', () {
    for (final e in v['seal'] as List) {
      final key = hx(e['keyHex'] as String);
      expect(seal(key, e['plain'] as String, e['aad'] as String, hx(e['ivHex'] as String)), e['sealed']);
      expect(utf8.decode(open(key, e['sealed'] as String, e['aad'] as String)), e['plain']);
      expect(() => open(key, e['sealed'] as String, '${e['aad']}x'), throwsA(isA<CryptoFailure>()));
    }
  });

  test('a device key sealed to the pairing code opens, and seals identically', () {
    final e = v['sealedDeviceKey'] as Map;
    final pk = pairingKey(hx(e['secretHex'] as String));
    expect(toHex(open(pk, e['sealed'] as String, 'pair:${e['deviceId']}')), e['deviceKeyHex']);
    expect(seal(pk, hx(e['deviceKeyHex'] as String), 'pair:${e['deviceId']}', hx(e['ivHex'] as String)), e['sealed']);
  });

  test('LAN frames in both directions', () {
    final d = v['derive'] as Map;
    final l = v['lan'] as Map;
    final sk = sessionKey(hx(d['deviceKeyHex'] as String), d['nonceC'] as String, d['nonceS'] as String);
    final s2c = l['s2c'] as Map, c2s = l['c2s'] as Map;
    expect(utf8.decode(open(sk, s2c['sealed'] as String, 'lan:dev-1:s2c')), s2c['plain']);
    expect(seal(sk, c2s['plain'] as String, 'lan:dev-1:c2s', hx(c2s['ivHex'] as String)), c2s['sealed']);
    // the direction is part of the seal: a frame cannot be reflected back
    expect(() => open(sk, s2c['sealed'] as String, 'lan:dev-1:c2s'), throwsA(isA<CryptoFailure>()));
  });

  test('cloud relay: a request seals identically and the computer\'s reply opens', () {
    final r = v['relay'] as Map;
    final key = hx(r['deviceKeyHex'] as String);
    final req = r['request'] as Map, res = r['response'] as Map;
    final draws = [hx(req['idHex'] as String), hx(req['ivHex'] as String)];
    final saved = randomBytes;
    randomBytes = (n) => draws.removeAt(0);
    try {
      final sealed = sealRelayRequest('dev-1', key, {'t': 'ping'}, now: req['ts'] as int);
      expect(sealed.id, req['id']);
      expect(sealed.sealed, req['sealed']);
    } finally {
      randomBytes = saved;
    }
    final opened = openRelayResponse('dev-1', key, res['sealed'] as String, req['id'] as String, now: res['ts'] as int);
    expect(opened, res['replies']);
    expect(
      () => openRelayResponse('dev-1', key, res['sealed'] as String, 'other', now: res['ts'] as int),
      throwsA(predicate((e) => '$e'.contains('different request'))),
    );
    expect(
      () => openRelayResponse('dev-1', key, res['sealed'] as String, req['id'] as String, now: (res['ts'] as int) + 6 * 60000),
      throwsA(predicate((e) => '$e'.contains('too old'))),
    );
    expect(sealRelayResponse('dev-1', key, jsonDecode(res['plain'] as String) as Map<String, dynamic>, iv: hx(res['ivHex'] as String)), res['sealed']);
  });

  test('pairing by approval: ECDH P-256, the confirmation number and the sealed key all agree', () {
    final e = v['ecdh'] as Map;
    final phone = ecdhFromPrivate(hx((e['phone'] as Map)['dHex'] as String));
    final machine = ecdhFromPrivate(hx((e['machine'] as Map)['dHex'] as String));
    expect(B64u.encode(phone.pub), (e['phone'] as Map)['pubB64u']);
    expect(B64u.encode(machine.pub), (e['machine'] as Map)['pubB64u']);
    final shared = ecdhShared(phone.priv, B64u.decode((e['machine'] as Map)['pubB64u'] as String));
    expect(toHex(shared), e['sharedHex']);
    expect(toHex(ecdhShared(machine.priv, phone.pub)), e['sharedHex']);
    final s = approvalSecrets(shared, phone.pub, machine.pub);
    expect(toHex(s.key), e['keyHex']);
    expect(s.confirm, e['confirm']);
    expect(toHex(open(s.key, e['sealedKey'] as String, 'pair:${e['deviceId']}')), e['deviceKeyHex']);
  });

  test('ECDH refuses a point that is not on the curve, and a malformed key', () {
    final k = ecdhGenerate();
    expect(k.pub.length, 65);
    final bad = Uint8List.fromList(k.pub)..[64] ^= 1;
    expect(() => ecdhShared(k.priv, bad), throwsA(isA<CryptoFailure>()));
    expect(() => ecdhShared(k.priv, k.pub.sublist(0, 33)), throwsA(isA<CryptoFailure>()));
    final other = ecdhGenerate();
    expect(ecdhShared(k.priv, other.pub), ecdhShared(other.priv, k.pub));
  });
}
