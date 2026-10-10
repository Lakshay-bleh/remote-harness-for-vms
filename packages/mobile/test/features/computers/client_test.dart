// Port of escanor-desktop packages/remote/src/phone/client.test.ts, cloud-pair.test.ts and the phone half of lan-pair.test.ts,
// against a stand-in desktop (fake_desktop.dart). interop_test.dart runs the same against the real desktop code.
import 'dart:async';
import 'dart:convert';

import 'package:escanor/features/computers/protocol/client.dart';
import 'package:escanor/features/computers/protocol/failure.dart';
import 'package:escanor/features/computers/protocol/lan_pair.dart';
import 'package:escanor/features/computers/protocol/protocol.dart';
import 'package:escanor/features/computers/protocol/secure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_desktop.dart';

void main() {
  late FakeDesktop c;
  final cleanups = <FutureOr<void> Function()>[];
  setUp(() async {
    c = await FakeDesktop.start();
  });
  tearDown(() async {
    for (final f in cleanups.reversed) {
      await f();
    }
    cleanups.clear();
    await c.close();
  });

  Future<PairedComputer> pairPhone({String? agentId, List<String>? lan}) => pairWithPayload(
    PairingPayload(code: c.createOffer(), machine: 'Test Laptop', lan: lan ?? [c.addr], agentId: agentId),
    'My Phone',
    const ClientEnv(lanTimeout: Duration(milliseconds: 1500)),
  );

  RelayTransport relayOf(FakeDesktop d) =>
      ({required agentId, required deviceId, required sealed}) => d.relay(deviceId, sealed);

  group('pairWithPayload', () {
    test('pairs over the local network using what the QR code says', () async {
      final paired = await pairPhone();
      expect(paired.name, 'Test Laptop');
      expect(paired.lan, [c.addr]);
      expect(paired.agentId, isNull);
      expect(c.devices[paired.id]?.name, 'My Phone');
      expect(B64u.encode(c.devices[paired.id]!.key), paired.key);
      expect(paired.key.length, greaterThan(40));
    });

    test('skips a dead address and uses the next one', () async {
      final paired = await pairPhone(lan: ['127.0.0.1:1', c.addr]);
      expect(c.devices.length, 1);
      expect(paired.lan, ['127.0.0.1:1', c.addr]);
    });

    test('a wrong code is a final answer, not a reason to keep trying', () async {
      c.createOffer();
      await expectLater(
        pairWithPayload(PairingPayload(code: 'AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA', machine: 'x', lan: [c.addr]), 'P'),
        throwsA(predicate((e) => '$e'.contains('did not match'))),
      );
      expect(c.devices, isEmpty);
    });

    test('says so when no address answers, and rejects a newer protocol', () async {
      await expectLater(
        pairWithPayload(
          const PairingPayload(code: 'AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA', machine: 'x', lan: ['127.0.0.1:1']),
          'P',
          const ClientEnv(lanTimeout: Duration(milliseconds: 500)),
        ),
        throwsA(anything),
      );
      await expectLater(
        pairWithPayload(const PairingPayload(v: 2, code: 'x', machine: 'x', lan: []), 'P'),
        throwsA(predicate((e) => '$e'.contains('newer version'))),
      );
    });

    test('never sends anything to an address outside the local network', () async {
      await expectLater(
        pairWithPayload(PairingPayload(code: c.createOffer(), machine: 'x', lan: const ['8.8.8.8:47625', 'example.com:47625']), 'P'),
        throwsA(predicate((e) => '$e'.contains('could not be reached on the local network'))),
      );
    });
  });

  group('ComputerClient over the local network', () {
    test('connects directly and runs requests', () async {
      final client = ComputerClient(await pairPhone());
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.lan);
      expect(client.route, ComputerRoute.lan);
      expect(await client.request(ClientMsg.ping()), [
        {'t': 'pong'},
      ]);
      final r = (await client.request(ClientMsg.call('a', 'system.stats'))).first;
      expect(r['t'], 'result');
      expect(r['id'], 'a');
      expect(r['result'], {'capability': 'system.stats', 'cpu': 4});
      expect(await client.request(ClientMsg.chat('b', 'volume up')), [
        {'t': 'reply', 'id': 'b', 'reply': 'heard: volume up', 'listenAgain': false},
      ]);
      expect(((await client.request(ClientMsg.list())).first['items'] as List).first['id'], 'system.stats');
      expect(((await client.request(ClientMsg.pending())).first['approvals'] as List).first['approvalId'], 'p1');
      // answered by type, not by id: these used to wait for the timeout on Wi-Fi
      expect((await client.request(ClientMsg.groups(), timeout: const Duration(seconds: 3))).first['t'], 'groups');
      expect((await client.request(ClientMsg.activity(limit: 20), timeout: const Duration(seconds: 3))).first['t'], 'activity');
      expect((await client.request(ClientMsg.requestGroup('os'), timeout: const Duration(seconds: 3))).first['status'], 'asked');
    });

    test('handles concurrent requests without mixing up their replies', () async {
      final client = ComputerClient(await pairPhone());
      cleanups.add(client.close);
      final replies = await Future.wait(['one', 'two', 'three', 'four'].indexed.map((e) => client.request(ClientMsg.chat('c${e.$1}', e.$2))));
      expect(replies.map((r) => r.first['reply']), ['heard: one', 'heard: two', 'heard: three', 'heard: four']);
    });

    test('receives pushed approvals and events after subscribing, and can answer an approval', () async {
      final client = ComputerClient(await pairPhone());
      cleanups.add(client.close);
      await client.connect();
      final pushed = <Msg>[];
      client.onPush(pushed.add);
      await client.subscribe(['events']);
      for (var i = 0; i < 100 && !pushed.any((m) => m['t'] == 'event'); i++) {
        c.push({
          't': 'event',
          'event': {'capabilityId': 'docker.pull', 'callId': 'x', 'type': 'progress', 'data': 1},
        }, channel: 'events');
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      c.push({'t': 'approval', 'approvalId': 'a9', 'capabilityId': 'docker.rm', 'describe': 'Delete', 'risk': 'destructive', 'input': {}});
      for (var i = 0; i < 100 && !pushed.any((m) => m['t'] == 'approval'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(pushed.map((m) => m['t']).toSet(), {'approval', 'event'});
      await client.request(ClientMsg.approve('a9', true));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(c.approvalsAnswered, [('a9', true)]);
    });

    test('refuses a computer that cannot prove it holds the key', () async {
      final paired = await pairPhone();
      final wrong = PairedComputer(id: paired.id, name: paired.name, key: B64u.encode(List.filled(32, 7)), lan: paired.lan);
      final client = ComputerClient(wrong, const ClientEnv(lanTimeout: Duration(milliseconds: 800)));
      await expectLater(client.connect(), throwsA(predicate((e) => '$e'.contains('not reachable'))));
      expect(client.route, isNull);
    });

    test('reports a computer that is off, when there is no cloud route', () async {
      final paired = await pairPhone();
      final client = ComputerClient(paired.copyWith(lan: ['127.0.0.1:1']), const ClientEnv(lanTimeout: Duration(milliseconds: 400)));
      await expectLater(client.connect(), throwsA(predicate((e) => '$e'.contains('not reachable'))));
    });
  });

  group('ComputerClient through the cloud relay', () {
    test('reaches the computer through the cloud when the local network does not', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      final client = ComputerClient(paired.copyWith(lan: ['127.0.0.1:1']), ClientEnv(relay: relayOf(c), lanTimeout: const Duration(milliseconds: 400)));
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.cloud);
      expect(await client.request(ClientMsg.chat('z', 'what is eating my ram')), [
        {'t': 'reply', 'id': 'z', 'reply': 'heard: what is eating my ram', 'listenAgain': false},
      ]);
      expect(((await client.request(ClientMsg.pending())).first['approvals'] as List).first['approvalId'], 'p1');
      // the cloud only ever held ciphertext
      expect(c.relayLog.join(' '), isNot(contains('eating my ram')));
      await client.subscribe(['events']); // harmless over the cloud
    });

    test('prefers the local network when both work', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      final client = ComputerClient(paired, ClientEnv(relay: relayOf(c)));
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.lan);
      await client.request(ClientMsg.ping());
      expect(c.relayLog, isEmpty);
    });

    test('falls back to the cloud, mid-conversation, if the local link drops', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      final cloud = await FakeDesktop.start(); // the same computer, still reachable through the cloud
      cloud.devices.addAll(c.devices);
      cleanups.add(cloud.close);
      final client = ComputerClient(paired, ClientEnv(relay: relayOf(cloud), lanTimeout: const Duration(milliseconds: 400)));
      cleanups.add(client.close);
      await client.connect();
      final routes = <ComputerRoute?>[];
      client.onRoute(routes.add);
      await c.close(); // the phone walks out of Wi-Fi range
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await client.request(ClientMsg.chat('m', 'still there?')), [
        {'t': 'reply', 'id': 'm', 'reply': 'heard: still there?', 'listenAgain': false},
      ]);
      expect(client.route, ComputerRoute.cloud);
      expect(routes, contains(ComputerRoute.cloud));
    });

    test('a chat the computer already received is not sent again over the cloud when the local link drops', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      final cloud = await FakeDesktop.start();
      cloud.devices.addAll(c.devices);
      cleanups.add(cloud.close);
      final client = ComputerClient(paired, ClientEnv(relay: relayOf(cloud), lanTimeout: const Duration(milliseconds: 400)));
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.lan);
      c.hold.add('chat');
      final asked = client.request(ClientMsg.chat('m', 'restart the server'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.taken.where((m) => m['t'] == 'chat'), hasLength(1), reason: 'it reached the computer');
      final failed = expectLater(asked, throwsA(isA<ComputerError>().having((e) => e.delivered, 'delivered', true)));
      await c.close(); // the link drops while the computer works on it
      await failed;
      expect(cloud.taken.where((m) => m['t'] == 'chat'), isEmpty, reason: 'sending it again could restart the server twice');
      expect(client.route, ComputerRoute.cloud, reason: 'later requests use the cloud');
    });

    test('a request that only reads is sent again over the cloud when the local link drops', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      final cloud = await FakeDesktop.start();
      cloud.devices.addAll(c.devices);
      cleanups.add(cloud.close);
      final client = ComputerClient(paired, ClientEnv(relay: relayOf(cloud), lanTimeout: const Duration(milliseconds: 400)));
      cleanups.add(client.close);
      await client.connect();
      c.hold.add('list');
      final asked = client.request(ClientMsg.list());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await c.close();
      expect(((await asked).first['items'] as List).first['id'], 'system.stats');
      expect(cloud.taken.where((m) => m['t'] == 'list'), hasLength(1));
    });

    test('a request that timed out after reaching the computer is marked, so it is not repeated', () async {
      final client = ComputerClient(await pairPhone());
      cleanups.add(client.close);
      await client.connect();
      c.hold.add('chat');
      await expectLater(
        client.request(ClientMsg.chat('t', 'slow'), timeout: const Duration(milliseconds: 200)),
        throwsA(isA<ComputerError>().having((e) => e.delivered, 'delivered', true).having((e) => e.message, 'message', 'The computer did not answer in time.')),
      );
    });

    test('a reply sealed for another request is refused', () async {
      final paired = await pairPhone(agentId: 'agent-1');
      String? first;
      final client = ComputerClient(
        paired.copyWith(lan: const []),
        ClientEnv(
          relay: ({required agentId, required deviceId, required sealed}) async {
            final answer = await c.relay(deviceId, sealed);
            return first ??= answer; // the cloud replays the first answer to every later request
          },
        ),
      );
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.cloud);
      expect((await client.request(ClientMsg.ping())).first['t'], 'pong');
      await expectLater(client.request(ClientMsg.ping()), throwsA(predicate((e) => '$e'.contains('different request'))));
    });
  });

  group('pairWithCode (through the cloud)', () {
    CloudDirectory cloudFor(FakeDesktop d, String agentId, {List<DesktopEntry> others = const [], List<String>? asked}) =>
        _Cloud(() async => [DesktopEntry(id: agentId, name: 'Work Laptop', online: true), ...others], (id, body) async {
          asked?.add(id);
          if (id != agentId) throw Exception('Not this computer.');
          try {
            final r = d.cloudPair(body);
            return (deviceId: r['deviceId'] as String, sealedKey: r['sealedKey'] as String);
          } on Exception catch (e) {
            throw Exception('$e'.replaceFirst('Exception: ', ''));
          }
        });

    test('pairs with just the code: finds the computer in the account, keeps its key and the cloud route', () async {
      final code = c.createOffer();
      final paired = await pairWithCode(code, 'My Phone', cloudFor(c, 'agent-1'));
      expect(paired.name, 'Work Laptop');
      expect(paired.agentId, 'agent-1');
      expect(paired.lan, isEmpty);
      expect(paired.key, B64u.encode(c.devices[paired.id]!.key));
      expect(B64u.decode(paired.key).length, 32);
    });

    test('skips computers that are not showing this code, and ignores ones that are offline', () async {
      final asked = <String>[];
      final code = c.createOffer();
      final paired = await pairWithCode(
        code,
        'My Phone',
        cloudFor(
          c,
          'agent-1',
          asked: asked,
          others: const [
            DesktopEntry(id: 'other-pc', name: 'Other', online: true),
            DesktopEntry(id: 'asleep', name: 'Asleep', online: false),
          ],
        ),
      );
      expect(paired.agentId, 'agent-1');
      expect(asked, isNot(contains('asleep')));
    });

    test('goes straight to the computer named by a scanned QR, and keeps its local addresses', () async {
      final asked = <String>[];
      final code = c.createOffer();
      final paired = await pairWithCode(
        code,
        'My Phone',
        cloudFor(
          c,
          'agent-1',
          asked: asked,
          others: const [DesktopEntry(id: 'other-pc', name: 'Other', online: true)],
        ),
        agentId: 'agent-1',
        machine: 'Work Laptop',
        lan: ['192.168.1.20:47625'],
      );
      expect(asked, ['agent-1']);
      expect(paired.lan, ['192.168.1.20:47625']);
    });

    test('says what to do when no computer is online, or none shows that code, or the code is malformed', () async {
      final code = c.createOffer();
      await expectLater(
        pairWithCode(code, 'P', _Cloud(() async => [], (_, _) async => (deviceId: '', sealedKey: ''))),
        throwsA(predicate((e) => '$e'.contains('online in your account'))),
      );
      await expectLater(
        pairWithCode(
          code,
          'P',
          _Cloud(() async => [const DesktopEntry(id: 'x', name: 'X', online: true)], (_, _) async => throw Exception('Not this computer.')),
        ),
        throwsA(predicate((e) => '$e'.contains('not showing on any of your computers'))),
      );
      await expectLater(pairWithCode('nonsense', 'P', cloudFor(c, 'agent-1')), throwsA(predicate((e) => '$e'.contains('not valid'))));
    });

    test('passes the computer’s own refusal through instead of hiding it', () async {
      await expectLater(
        pairWithCode('AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA', 'P', cloudFor(c, 'agent-1')),
        throwsA(predicate((e) => '$e'.contains('No pairing is open on this computer.'))),
      );
    });
  });

  group('pairing on the same network with only an address', () {
    test('pairs after the person approves, and both screens show the same number', () async {
      var shown = '';
      final got = await phoneAskLan('http://${c.addr}', 'Pixel', LanAskOptions(onConfirm: (n) => shown = n, pollMs: 10));
      expect(c.asked, hasLength(1));
      expect(shown, matches(RegExp(r'^\d{3} \d{3}$')));
      expect(c.asked.first, shown);
      expect(B64u.encode(got.key), B64u.encode(c.devices[got.deviceId]!.key));
      expect(got.machineName, 'Test Laptop');
    });

    test('pairByAddress takes just an address and returns a computer the LAN route can use', () async {
      final paired = await pairByAddress(c.addr, 'Pixel', const LanAskOptions(pollMs: 10));
      expect(paired.lan, [c.addr]);
      expect(paired.name, 'Test Laptop');
      expect(paired.agentId, isNull);
      final client = ComputerClient(paired);
      cleanups.add(client.close);
      expect(await client.connect(), ComputerRoute.lan);
    });

    test('adds no phone when the person says no', () async {
      c.ask = (_, _) async => false;
      await expectLater(phoneAskLan('http://${c.addr}', 'Pixel', const LanAskOptions(pollMs: 10)), throwsA(predicate((e) => '$e'.contains('said no'))));
      expect(c.devices, isEmpty);
    });

    test('can be cancelled while waiting', () async {
      c.ask = (_, _) => Completer<bool>().future; // nobody answers
      final cancel = CancelToken();
      final f = phoneAskLan(
        'http://${c.addr}',
        'Pixel',
        LanAskOptions(pollMs: 20, cancel: cancel, onConfirm: (_) => Timer(const Duration(milliseconds: 60), cancel.cancel)),
      );
      await expectLater(f, throwsA(predicate((e) => '$e'.contains('cancelled'))));
    });

    test('says plainly when nothing answers at the address, and refuses addresses outside the network', () async {
      await expectLater(pairByAddress('127.0.0.1:19', 'P'), throwsA(predicate((e) => '$e'.contains('Nothing answered at 127.0.0.1:19'))));
      await expectLater(pairByAddress('8.8.8.8', 'P'), throwsA(predicate((e) => '$e'.contains('Enter the computer’s address'))));
    });
  });

  group('isLocalAddress / normalizeLanAddress', () {
    test('only private, link-local, CGNAT, loopback and .local hosts count', () {
      for (final a in [
        '10.0.0.5',
        '192.168.1.20:47625',
        '172.16.0.1',
        '172.31.255.1',
        '169.254.1.1',
        '100.64.0.1',
        '100.127.1.1',
        '127.0.0.1',
        'localhost',
        'my-pc.local',
        'http://192.168.0.2:1/x',
      ]) {
        expect(isLocalAddress(a), isTrue, reason: a);
      }
      for (final a in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '192.169.1.1', 'example.com', '300.1.1.1', '', '1.2.3']) {
        expect(isLocalAddress(a), isFalse, reason: a);
      }
    });
    test('normalises an address and assumes the usual port', () {
      expect(normalizeLanAddress(' 192.168.1.20 '), '192.168.1.20:47625');
      expect(normalizeLanAddress('http://192.168.1.20:47625/'), '192.168.1.20:47625');
      expect(normalizeLanAddress('192.168.1.20:99999'), isNull);
    });
  });

  test('isClientMsg accepts what the computer accepts', () {
    expect(isClientMsg(ClientMsg.chat('a', 'hi', fresh: true)), isTrue);
    expect(isClientMsg({'t': 'chat', 'id': 'a', 'text': ''}), isFalse);
    expect(isClientMsg({'t': 'chat', 'id': 'a', 'text': 'x' * 4001}), isFalse);
    expect(isClientMsg(ClientMsg.activity(limit: 20, before: '2026-10-04T10:00:00Z')), isTrue);
    expect(isClientMsg({'t': 'activity', 'limit': 51}), isFalse);
    expect(isClientMsg(ClientMsg.requestGroup('os')), isTrue);
    expect(isClientMsg(ClientMsg.requestGroup('Bad Group')), isFalse);
    expect(isClientMsg(ClientMsg.subscribe(['events', 'stats'])), isTrue);
    expect(
      isClientMsg({
        't': 'subscribe',
        'channels': ['all'],
      }),
      isFalse,
    );
    expect(isClientMsg({'t': 'nope'}), isFalse);
    expect(jsonEncode(ClientMsg.call('i', 'system.processes', {'limit': 6})), '{"t":"call","id":"i","capability":"system.processes","input":{"limit":6}}');
  });
}

class _Cloud implements CloudDirectory {
  _Cloud(this._computers, this._pair);
  final Future<List<DesktopEntry>> Function() _computers;
  final Future<({String deviceId, String sealedKey})> Function(String agentId, Map<String, dynamic> body) _pair;
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
