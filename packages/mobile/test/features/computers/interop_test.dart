// End to end against the REAL Escanor Desktop remote code (escanor-desktop/packages/remote/src, run with node by
// interop/desktop_harness.mts): pairing by code over the cloud and over Wi-Fi, pairing by approval, the encrypted LAN session and
// the encrypted cloud relay through the backend API. Skipped where node, tsx, ws or the desktop checkout are not on this machine.
import 'dart:convert';
import 'dart:io';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/features/computers/cloud.dart';
import 'package:escanor/features/computers/computer_api.dart';
import 'package:escanor/features/computers/pairing.dart';
import 'package:escanor/features/computers/protocol/client.dart';
import 'package:escanor/features/computers/protocol/lan_pair.dart';
import 'package:escanor/features/computers/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final home = Platform.environment['HOME'] ?? '';
final node = Platform.environment['ESCANOR_NODE'] ?? '$home/.nvm/versions/node/v22.23.2/bin/node';
// Node tools: `npm install` once in test/features/computers/interop (or point ESCANOR_TSX / ESCANOR_WS elsewhere).
final _tools = '${Directory.current.path}/test/features/computers/interop/node_modules';
final tsx = Platform.environment['ESCANOR_TSX'] ?? '$_tools/tsx/dist/cli.mjs';
final desktop = Platform.environment['ESCANOR_DESKTOP'] ?? '${Directory.current.parent.path}/escanor-desktop';
final wsPath = Platform.environment['ESCANOR_WS'] ?? '$_tools/ws';

String? get missing {
  for (final p in [node, tsx, '$desktop/packages/remote/src/gateway.ts', '$wsPath/wrapper.mjs']) {
    if (!File(p).existsSync()) return 'not on this machine: $p';
  }
  return null;
}

void main() {
  final skip = missing;
  late Process proc;
  late String gateway;
  late String apiBase;
  late String agentId;
  late Api cloudApi;

  setUpAll(() async {
    if (skip != null) return;
    await Storage.initForTest();
    proc = await Process.start(
      node,
      [tsx, 'test/features/computers/interop/desktop_harness.mts'],
      environment: {'DESKTOP': desktop, 'WS_PATH': wsPath, 'PATH': '${File(node).parent.path}:${Platform.environment['PATH']}'},
    );
    proc.stderr.transform(utf8.decoder).listen((e) => stderr.write('[desktop] $e'));
    final first = await proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 60));
    final info = jsonDecode(first) as Map<String, dynamic>;
    gateway = info['gateway'] as String;
    apiBase = info['api'] as String;
    agentId = info['agentId'] as String;
    cloudApi = Api(base: apiBase);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await proc.stdin.close();
    proc.kill();
  });

  Future<Map<String, dynamic>> control(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$apiBase$path');
    final res = method == 'GET' ? await http.get(uri) : await http.post(uri, body: jsonEncode(body ?? {}));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deviceOnDesktop(String id) async =>
      ((await control('GET', '/test/state'))['devices'] as List).cast<Map<String, dynamic>>().firstWhere((d) => d['id'] == id);

  test('cloud: lists this account’s desktops and pairs with just the code, through the real relay link', () async {
    final offer = await control('POST', '/test/offer');
    final desks = await cloudApi.desktops();
    expect(desks.map((d) => d.id), [agentId]); // the non-desktop machine is left out
    expect(desks.single.online, isTrue);
    final paired = await pairComputer(parseEntry(offer['code'] as String)!, 'Interop Phone', PairOptions(cloud: ApiCloudDirectory(cloudApi)));
    expect(paired.agentId, agentId);
    expect(paired.name, 'Interop Laptop');
    final d = await deviceOnDesktop(paired.id);
    expect(d['name'], 'Interop Phone');
    expect(d['key'], paired.key, reason: 'the phone unsealed exactly the key the desktop stored');

    // and talks to it through the cloud, end to end encrypted
    final client = ComputerClient(paired.copyWith(lan: const []), ClientEnv(relay: apiRelay(cloudApi)));
    addTearDown(client.close);
    expect(await client.connect(), ComputerRoute.cloud);
    expect(await client.request(ClientMsg.chat('z1', 'what is eating my ram', fresh: true)), [
      {'t': 'reply', 'id': 'z1', 'reply': 'heard: what is eating my ram (fresh)', 'listenAgain': false},
    ]);
    expect(((await client.request(ClientMsg.groups())).first['items'] as List).first['label'], 'Open apps and websites');
    expect((await client.request(ClientMsg.activity(limit: 20))).first['more'], false);
    final cloudText = (await control('GET', '/test/state'))['cloudText'] as String;
    expect(cloudText, isNot(contains('eating my ram')), reason: 'the cloud only carried ciphertext');
  }, skip: skip);

  test('Wi-Fi: pairs with the QR payload and runs an authenticated, sealed session with the real gateway', () async {
    final offer = await control('POST', '/test/offer');
    final qr = jsonEncode({
      'v': 1,
      'code': offer['code'],
      'machine': 'Interop Laptop',
      'lan': [gateway],
      'agentId': null,
    });
    final paired = await pairComputer(parseEntry(qr)!, 'Wifi Phone', PairOptions(mode: PairMode.lan, cloud: ApiCloudDirectory(cloudApi)));
    expect(paired.lan, [gateway]);
    expect((await deviceOnDesktop(paired.id))['key'], paired.key);

    final client = ComputerClient(paired);
    addTearDown(client.close);
    final pushed = <Msg>[];
    client.onPush(pushed.add);
    expect(await client.connect(), ComputerRoute.lan);
    expect(await client.request(ClientMsg.ping()), [
      {'t': 'pong'},
    ]);
    final r = (await client.request(ClientMsg.call('c1', 'system.processes', {'limit': 6}))).single;
    expect(r['result'], {
      'capability': 'system.processes',
      'input': {'limit': 6},
      'cpu': 4,
    });
    final replies = await Future.wait([for (var i = 0; i < 5; i++) client.request(ClientMsg.chat('m$i', 'n$i'))]);
    expect(replies.map((x) => x.single['reply']), [for (var i = 0; i < 5; i++) 'heard: n$i']);
    expect(((await client.request(ClientMsg.pending())).single['approvals'] as List).single['approvalId'], 'p1');
    expect((await client.request(ClientMsg.groups(), timeout: const Duration(seconds: 5))).single['t'], 'groups');
    expect((await client.request(ClientMsg.requestGroup('os'), timeout: const Duration(seconds: 5))).single['status'], 'asked');
    expect(((await client.request(ClientMsg.activity(limit: 5), timeout: const Duration(seconds: 5))).single['items'] as List).length, 1);

    await control('POST', '/test/approval', {
      'approvalId': 'a9',
      'capabilityId': 'docker.rm',
      'describe': 'Delete',
      'risk': 'destructive',
      'input': {'name': 'x'},
    });
    for (var i = 0; i < 100 && !pushed.any((m) => m['t'] == 'approval'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(pushed.firstWhere((m) => m['t'] == 'approval')['approvalId'], 'a9');
    await client.request(ClientMsg.approve('a9', true));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect((await control('GET', '/test/state'))['answered'], [
      ['a9', true],
    ]);
  }, skip: skip);

  test('Wi-Fi without a code: both screens show the same number, and the key works', () async {
    String? shown;
    final paired = await pairOnWifi(gateway, 'Approval Phone', LanAskOptions(onConfirm: (n) => shown = n, pollMs: 50));
    final confirms = ((await control('GET', '/test/state'))['confirms'] as List).cast<String>();
    expect(confirms.last, shown);
    expect(paired.name, 'Interop Laptop');
    expect((await deviceOnDesktop(paired.id))['key'], paired.key);
    final client = ComputerClient(paired);
    addTearDown(client.close);
    expect(await client.connect(), ComputerRoute.lan);
  }, skip: skip);

  test('a phone whose key is wrong is refused by the real gateway', () async {
    final offer = await control('POST', '/test/offer');
    final paired = await pairWithPayload(PairingPayload(code: offer['code'] as String, machine: 'x', lan: [gateway]), 'Bad Phone');
    final wrong = PairedComputer(
      id: paired.id,
      name: paired.name,
      key: paired.key.replaceRange(0, 4, paired.key.startsWith('AAAA') ? 'BBBB' : 'AAAA'),
      lan: paired.lan,
    );
    final client = ComputerClient(wrong, const ClientEnv(lanTimeout: Duration(seconds: 2)));
    await expectLater(client.connect(), throwsA(predicate((e) => '$e'.contains('not reachable'))));
  }, skip: skip);

  test('chatWithComputer: falls back to the cloud when the Wi-Fi gateway goes away', () async {
    final offer = await control('POST', '/test/offer');
    final qr = jsonEncode({
      'v': 1,
      'code': offer['code'],
      'machine': 'Interop Laptop',
      'lan': [gateway],
      'agentId': agentId,
    });
    final paired = await pairComputer(parseEntry(qr)!, 'Voice Phone', PairOptions(cloud: ApiCloudDirectory(cloudApi)));
    expect(paired.agentId, agentId);
    expect(await chatWithComputerUsing(paired, 'hello there', relay: apiRelay(cloudApi)), 'heard: hello there');
    await control('POST', '/test/close-gateway');
    expect(
      await chatWithComputerUsing(
        paired,
        'still there?',
        relay: apiRelay(cloudApi),
        env: const ClientEnv(lanTimeout: Duration(milliseconds: 500)),
      ),
      'heard: still there?',
    );
    gateway = (await control('POST', '/test/reopen-gateway'))['lan'] as String;
  }, skip: skip);
}
