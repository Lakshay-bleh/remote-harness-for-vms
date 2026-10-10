// Port of computer/pairing.test.ts.
import 'dart:convert';

import 'package:escanor/features/computers/pairing.dart';
import 'package:escanor/features/computers/protocol/client.dart';
import 'package:escanor/features/computers/protocol/failure.dart';
import 'package:escanor/features/computers/protocol/protocol.dart';
import 'package:escanor/features/computers/protocol/secure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeCloud implements CloudDirectory {
  FakeCloud(this._computers, this._pair);
  final Future<List<DesktopEntry>> Function() _computers;
  final Future<({String deviceId, String sealedKey})> Function(String agentId, Map<String, String> body) _pair;
  @override
  Future<List<DesktopEntry>> computers() => _computers();
  @override
  Future<({String deviceId, String sealedKey})> pair(
    String agentId, {
    required String sel,
    required String nonce,
    required String proof,
    required String name,
  }) => _pair(agentId, {'sel': sel, 'nonce': nonce, 'proof': proof, 'name': name});
}

/// A computer showing a code: it checks the proof like the real desktop does and seals a device key to the code.
({String code, FakeCloud cloud, List<String> asked, List<int> secret}) fakeDesktop([String id = 'agent-1', String name = 'Work Laptop']) {
  final secret = randomBytes(20);
  final code = formatCode(secret);
  final asked = <String>[];
  final cloud = FakeCloud(() async => [DesktopEntry(id: id, name: name, online: true)], (agentId, body) async {
    asked.add(agentId);
    if (agentId != id) throw const ComputerError('Not this computer.');
    if (body['sel'] != pairSelector(secret)) throw const ComputerError('Not this computer.');
    if (B64u.encode(pairProof(secret, body['nonce']!, body['name']!)) != body['proof']) throw const ComputerError('That code did not match.');
    return (deviceId: 'dev-1', sealedKey: seal(pairingKey(secret), randomBytes(32), 'pair:dev-1'));
  });
  return (code: code, cloud: cloud, asked: asked, secret: secret);
}

void main() {
  group('parseEntry', () {
    test('reads a typed code in any case, with or without dashes and spaces', () {
      final d = fakeDesktop();
      for (final typed in [d.code, d.code.toLowerCase(), d.code.replaceAll('-', ''), '  ${d.code.replaceAll('-', ' ')}  ']) {
        expect(parseEntry(typed)?.code, d.code); // always the canonical form
      }
    });

    test('reads a scanned QR payload, keeping the computer and its addresses', () {
      final d = fakeDesktop();
      final e = parseEntry(
        jsonEncode({
          'v': 1,
          'code': d.code,
          'machine': 'Work Laptop',
          'lan': ['192.168.1.20:47625'],
          'agentId': 'agent-1',
        }),
      );
      expect(e?.payload, PairingPayload(code: d.code, machine: 'Work Laptop', lan: const ['192.168.1.20:47625'], agentId: 'agent-1'));
    });

    test('rejects nonsense, a code of the wrong length and foreign QR codes', () {
      for (final bad in [
        '',
        'hello',
        'ABCD-EFGH',
        'https://example.com/x',
        '{"a":1}',
        jsonEncode({'v': 2, 'code': 'x'}),
      ]) {
        expect(parseEntry(bad), isNull, reason: bad);
      }
    });
  });

  group('normalizeAddress', () {
    test('accepts an address on the local network, with or without a port, and rejects anything else', () {
      expect(normalizeAddress(' 192.168.1.20:47625 '), '192.168.1.20:47625');
      expect(normalizeAddress('http://192.168.1.20:47625/'), '192.168.1.20:47625');
      expect(normalizeAddress('192.168.1.20'), '192.168.1.20:47625'); // the usual port is assumed
      for (final bad in ['', 'nonsense', '192.168.1.20:99999', 'a b:1', '8.8.8.8', 'example.com:47625']) {
        expect(normalizeAddress(bad), isNull, reason: bad);
      }
    });
  });

  group('pairComputer', () {
    test('pairs from anywhere with just the code (the default): no address involved', () async {
      final d = fakeDesktop();
      final paired = await pairComputer(parseEntry(d.code)!, 'My Phone', PairOptions(cloud: d.cloud));
      expect(paired.agentId, 'agent-1');
      expect(paired.name, 'Work Laptop');
      expect(paired.lan, isEmpty);
    });

    test('does not ask for an address in cloud mode even when the person typed one', () async {
      final d = fakeDesktop();
      final paired = await pairComputer(parseEntry(d.code)!, 'My Phone', PairOptions(cloud: d.cloud, lanAddress: '10.0.0.5:47625'));
      expect(paired.lan, isEmpty);
    });

    test('local mode needs an address (typed or in the QR) and says so', () async {
      final d = fakeDesktop();
      final isAddress = throwsA(predicate((e) => '$e'.toLowerCase().contains('address')));
      await expectLater(pairComputer(parseEntry(d.code)!, 'P', PairOptions(mode: PairMode.lan, cloud: d.cloud)), isAddress);
      await expectLater(pairComputer(parseEntry(d.code)!, 'P', PairOptions(mode: PairMode.lan, cloud: d.cloud, lanAddress: 'nonsense')), isAddress);
    });

    test('a scanned QR goes straight to its computer, and a wrong code is reported (never retried on Wi-Fi)', () async {
      final d = fakeDesktop();
      final wrong = formatCode(randomBytes(20));
      final e = parseEntry(
        jsonEncode({
          'v': 1,
          'code': wrong,
          'machine': 'Work Laptop',
          'lan': ['192.168.1.20:47625'],
          'agentId': 'agent-1',
        }),
      )!;
      await expectLater(pairComputer(e, 'P', PairOptions(cloud: d.cloud)), throwsA(predicate((e) => '$e'.contains('not showing on any of your computers'))));
      expect(d.asked, ['agent-1']);
    });

    test('falls back to the QR’s local addresses only when the cloud itself cannot be reached', () async {
      final d = fakeDesktop();
      final offline = FakeCloud(
        () async => throw const ComputerError('Could not reach Escanor. Check your connection.'),
        (_, _) async => throw const ComputerError('Could not reach Escanor. Check your connection.'),
      );
      final e = parseEntry(
        jsonEncode({
          'v': 1,
          'code': d.code,
          'machine': 'Work Laptop',
          'lan': ['192.168.1.20:47625'],
          'agentId': 'agent-1',
        }),
      )!;
      String? triedLan;
      final client = MockClient((req) async {
        triedLan = '${req.url}';
        throw http.ClientException('network failed');
      });
      await expectLater(
        pairComputer(
          e,
          'P',
          PairOptions(
            cloud: offline,
            env: ClientEnv(client: client, lanTimeout: const Duration(milliseconds: 50)),
          ),
        ),
        throwsA(anything),
      );
      expect(triedLan, contains('192.168.1.20:47625/pair'));
    });

    test('parseCode round-trips what the desktop shows', () {
      final d = fakeDesktop();
      expect(parseCode(d.code), d.secret);
    });
  });
}
