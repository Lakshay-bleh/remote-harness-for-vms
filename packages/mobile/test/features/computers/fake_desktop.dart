// A stand-in for Escanor Desktop's local gateway and its cloud relay (gateway.ts, pairing.ts, lan-approval.ts, relay.ts),
// written with this port's own crypto from the computer's side. The real desktop is exercised by interop_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:escanor/features/computers/protocol/protocol.dart';
import 'package:escanor/features/computers/protocol/relay_seal.dart';
import 'package:escanor/features/computers/protocol/secure.dart';

class FakeDevice {
  FakeDevice(this.id, this.name, this.key);
  final String id;
  final String name;
  final Uint8List key;
}

class FakeDesktop {
  FakeDesktop._(this._server);
  final HttpServer? _server;

  /// The computer without its local gateway: only its cloud relay (no sockets, so it runs inside widget tests).
  FakeDesktop.cloudOnly() : _server = null;
  final devices = <String, FakeDevice>{};
  final approvalsAnswered = <(String, bool)>[];
  final _sessions = <_Session>{};
  Uint8List? _secret;
  int _failures = 0;
  int _n = 0;

  /// Pairing without a code: what the person at the computer answers.
  Future<bool> Function(String confirm, String deviceName) ask = (_, _) async => true;
  final asked = <String>[];
  final _asks = <String, Map<String, dynamic>>{};

  /// The relay's record of everything that crossed the cloud (it must only ever be ciphertext).
  final relayLog = <String>[];

  int get port => _server!.port;
  String get addr => '127.0.0.1:$port';

  static Future<FakeDesktop> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final d = FakeDesktop._(server);
    server.listen(d._handle);
    return d;
  }

  Future<void> close() async {
    for (final s in _sessions.toList()) {
      await s.ws.close();
    }
    await _server?.close(force: true);
  }

  /// A new pairing offer: its code.
  String createOffer() {
    final s = newPairingSecret();
    _secret = s.bytes;
    _failures = 0;
    return s.code;
  }

  /// A phone paired with this computer (as if it had paired earlier).
  FakeDevice addDevice(String name) => _add(name);

  FakeDevice _add(String name) {
    final d = FakeDevice(B64u.encode(randomBytes(12)), name, randomBytes(32));
    devices[d.id] = d;
    return d;
  }

  /// The computer's half of a redeem (LAN /pair and the cloud `pair` action). Returns {deviceId, sealedKey} or an error text.
  ({Map<String, dynamic>? ok, String? error}) redeem(String nonce, String proof, String name) {
    final secret = _secret;
    if (secret == null) return (ok: null, error: 'There is no active pairing. Start one on the computer.');
    var good = false;
    try {
      good = timingSafeEqual(pairProof(secret, nonce, name), B64u.decode(proof));
    } catch (_) {}
    if (!good) {
      if (++_failures >= 5) _secret = null;
      return (ok: null, error: 'That pairing code did not match.');
    }
    _secret = null;
    final d = _add(name);
    return (ok: {'deviceId': d.id, 'sealedKey': seal(pairingKey(secret), d.key, 'pair:${d.id}')}, error: null);
  }

  /// The computer's half of a cloud pairing (relay.ts answerPair).
  Map<String, dynamic> cloudPair(Map<String, dynamic> body) {
    final secret = _secret;
    if (secret == null) throw Exception('No pairing is open on this computer.');
    if (body['sel'] != pairSelector(secret)) throw Exception('Not this computer.');
    final r = redeem('${body['nonce']}', '${body['proof']}', '${body['name']}');
    if (r.error != null) throw Exception(r.error == 'That pairing code did not match.' ? 'That code did not match.' : r.error);
    return r.ok!;
  }

  /// The computer's half of the cloud relay (relay.ts answer): open, handle, seal the answer.
  Future<String> relay(String deviceId, String sealed) async {
    relayLog.add(sealed);
    final d = devices[deviceId];
    if (d == null) throw Exception('Not allowed.');
    Map<String, dynamic> req;
    try {
      req = openRelayRequest(deviceId, d.key, sealed);
    } catch (_) {
      throw Exception('Not allowed.');
    }
    final replies = await handle(Map<String, dynamic>.from(req['m'] as Map));
    final out = sealRelayResponse(deviceId, d.key, {'id': req['id'], 'ts': DateTime.now().millisecondsSinceEpoch, 'replies': replies});
    relayLog.add(out);
    return out;
  }

  /// Requests of these types are taken but not answered (the computer is busy with them), and every one taken is recorded.
  final hold = <String>{};
  final taken = <Msg>[];

  /// What the computer answers (handler.ts with a simple backend).
  Future<List<Msg>> handle(Msg m) async {
    if (!isClientMsg(m)) {
      return [
        {'t': 'error', 'message': 'That request was not understood.'},
      ];
    }
    taken.add(m);
    if (hold.contains(m['t'])) await Completer<void>().future; // never answered
    switch (m['t']) {
      case 'ping':
        return [
          {'t': 'pong'},
        ];
      case 'list':
        return [
          {
            't': 'capabilities',
            'items': [
              {
                'id': 'system.stats',
                'group': 'system',
                'describe': 'Stats',
                'risk': 'read',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        ];
      case 'pending':
        return [
          {
            't': 'pending',
            'approvals': [
              {'approvalId': 'p1', 'capabilityId': 'docker.rm', 'describe': 'Delete', 'risk': 'destructive', 'input': {}},
            ],
          },
        ];
      case 'call':
        return [
          {
            't': 'result',
            'id': m['id'],
            'ok': true,
            'result': {'capability': m['capability'], 'cpu': 4},
          },
        ];
      case 'chat':
        await Future<void>.delayed(Duration(milliseconds: 5 * ((m['text'] as String).length % 4)));
        return [
          {'t': 'reply', 'id': m['id'], 'reply': 'heard: ${m['text']}', 'listenAgain': false},
        ];
      case 'approve':
        approvalsAnswered.add((m['approvalId'] as String, m['ok'] as bool));
        return [];
      case 'groups':
        return [
          {
            't': 'groups',
            'items': [
              {'id': 'os', 'label': 'Open apps and websites', 'about': 'x', 'enabled': false},
            ],
          },
        ];
      case 'request_group':
        return [
          {'t': 'group_request', 'group': m['group'], 'status': 'asked'},
        ];
      case 'activity':
        return [
          {
            't': 'activity',
            'items': [
              {'at': '2026-10-04T10:00:00Z', 'capabilityId': 'os.open_url', 'caller': 'voice', 'risk': 'read', 'outcome': 'ok', 'ms': 3},
            ],
            'more': false,
          },
        ];
    }
    return [];
  }

  /// Push to every session (approvals always; events to subscribers).
  void push(Msg m, {String? channel}) {
    for (final s in _sessions) {
      if (channel == null || s.subscribed.contains(channel)) s.send(m);
    }
  }

  void _json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/session' && WebSocketTransformer.isUpgradeRequest(req)) {
      _session(await WebSocketTransformer.upgrade(req));
      return;
    }
    final body = req.method == 'POST' ? await utf8.decoder.bind(req).join() : '';
    if (req.method == 'GET' && path == '/info') {
      return _json(req.response, 200, {'app': 'escanor-desktop', 'v': 1, 'name': 'Test Laptop', 'pairing': _secret != null});
    }
    if (req.method == 'POST' && path == '/pair') {
      final b = jsonDecode(body) as Map;
      final r = redeem('${b['nonce']}', '${b['proof']}', '${(b['device'] as Map)['name']}');
      return r.ok != null ? _json(req.response, 200, r.ok!) : _json(req.response, 403, {'error': r.error});
    }
    if (req.method == 'POST' && path == '/pair/ask') {
      final b = jsonDecode(body) as Map;
      final phonePub = B64u.decode('${b['pub']}');
      final mine = ecdhGenerate();
      final s = approvalSecrets(ecdhShared(mine.priv, phonePub), phonePub, mine.pub);
      final id = 'ask${++_n}';
      final entry = <String, dynamic>{'status': 'pending'};
      _asks[id] = entry;
      final name = '${(b['device'] as Map)['name']}';
      asked.add(s.confirm);
      unawaited(
        ask(s.confirm, name).then((ok) {
          if (!ok) {
            entry['status'] = 'denied';
            return;
          }
          final d = _add(name);
          entry.addAll({'status': 'approved', 'deviceId': d.id, 'sealedKey': seal(s.key, d.key, 'pair:${d.id}')});
        }),
      );
      return _json(req.response, 200, {'id': id, 'pub': B64u.encode(mine.pub), 'ttlMs': 110000});
    }
    if (req.method == 'GET' && path.startsWith('/pair/ask/')) {
      final e = _asks[Uri.decodeComponent(path.substring('/pair/ask/'.length))];
      if (e == null) return _json(req.response, 404, {'error': 'That request is gone. Ask again.'});
      return _json(
        req.response,
        200,
        e['status'] == 'approved'
            ? {
                ...e,
                'machine': {'name': 'Test Laptop'},
              }
            : e,
      );
    }
    _json(req.response, 404, {'error': 'not found'});
  }

  void _session(WebSocket ws) {
    final queue = <String>[];
    Completer<void>? wake;
    var closed = false;
    ws.listen(
      (d) {
        queue.add('$d');
        wake?.complete();
        wake = null;
      },
      onDone: () {
        closed = true;
        wake?.complete();
        wake = null;
      },
    );
    Future<Map> next() async {
      while (queue.isEmpty) {
        if (closed) throw Exception('closed');
        await (wake = Completer<void>()).future;
      }
      return jsonDecode(queue.removeAt(0)) as Map;
    }

    () async {
      _Session? s;
      try {
        final hello = await next();
        final device = devices[hello['deviceId']];
        final key = device?.key ?? randomBytes(32);
        final nonceC = '${hello['nonceC']}';
        final nonceS = B64u.encode(randomBytes(16));
        ws.add(jsonEncode({'t': 'challenge', 'nonceS': nonceS, 'proof': B64u.encode(serverProof(key, nonceC, nonceS))}));
        final auth = await next();
        if (device == null || !timingSafeEqual(clientProof(key, nonceC, nonceS), B64u.decode('${auth['proof']}'))) throw Exception('auth');
        final sk = sessionKey(key, nonceC, nonceS);
        s = _Session(ws, sk, device.id);
        _sessions.add(s);
        s.send({
          't': 'hello',
          'machine': {'name': 'Test Laptop', 'hostname': 'box', 'os': 'linux', 'appVersion': '0.1.0'},
        });
        var seqIn = 0;
        for (;;) {
          final f = await next();
          final j = jsonDecode(utf8.decode(open(sk, '${f['c']}', 'lan:${device.id}:c2s'))) as Map;
          if (!((j['s'] as int) > seqIn)) {
            await ws.close(4400, 'replay');
            return;
          }
          seqIn = j['s'] as int;
          final m = Map<String, dynamic>.from(j['m'] as Map);
          if (m['t'] == 'subscribe') {
            s.subscribed.addAll((m['channels'] as List).cast<String>());
            continue;
          }
          final session = s;
          unawaited(
            handle(m).then((replies) {
              for (final r in replies) {
                session.send(r);
              }
            }),
          );
        }
      } catch (_) {
        await ws.close(s == null ? 4401 : 4400);
      } finally {
        _sessions.remove(s);
      }
    }();
  }
}

class _Session {
  _Session(this.ws, this.sk, this.deviceId);
  final WebSocket ws;
  final Uint8List sk;
  final String deviceId;
  final subscribed = <String>{};
  int seqOut = 0;
  void send(Msg m) {
    seqOut += 1;
    ws.add(
      jsonEncode({
        'c': seal(sk, jsonEncode({'s': seqOut, 'm': m}), 'lan:$deviceId:s2c'),
      }),
    );
  }
}
