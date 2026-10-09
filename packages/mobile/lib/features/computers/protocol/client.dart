/// Port of escanor-desktop packages/remote/src/phone/client.ts: the phone's side of the channel.
///
/// Route: LAN first (direct, free, nothing leaves the building); if the computer is not reachable that way, the Escanor cloud
/// relay (end-to-end encrypted, the cloud only passes sealed messages along).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'failure.dart';
import 'lan_pair.dart';
import 'protocol.dart';
import 'redeem.dart';
import 'relay_seal.dart';
import 'secure.dart';

/// A computer this phone is paired with.
class PairedComputer {
  const PairedComputer({required this.id, required this.name, this.key = '', this.lan = const [], this.agentId, this.pairedAt = ''});

  /// The device id this phone was given.
  final String id;
  final String name;

  /// 32-byte device key, base64url. Kept in the Keychain / Keystore (see storage.dart), never in ordinary preferences.
  final String key;

  /// `host:port` addresses to try on the local network, best first.
  final List<String> lan;

  /// Escanor machine id, for the cloud route.
  final String? agentId;

  /// ISO time.
  final String pairedAt;

  PairedComputer copyWith({List<String>? lan, String? name}) =>
      PairedComputer(id: id, name: name ?? this.name, key: key, lan: lan ?? this.lan, agentId: agentId, pairedAt: pairedAt);

  /// Everything except the key (which is a secret and is stored apart).
  Map<String, dynamic> toMetaJson() => {'id': id, 'name': name, 'lan': lan, 'agentId': agentId, 'pairedAt': pairedAt};

  static PairedComputer? fromMetaJson(Object? j, String key) {
    if (j is! Map || j['id'] is! String) return null;
    return PairedComputer(
      id: j['id'] as String,
      name: j['name'] is String ? j['name'] as String : 'My computer',
      key: key,
      lan: j['lan'] is List
          ? [
              for (final a in j['lan'] as List)
                if (a is String) a,
            ]
          : const [],
      agentId: j['agentId'] is String ? j['agentId'] as String : null,
      pairedAt: j['pairedAt'] is String ? j['pairedAt'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PairedComputer &&
      other.id == id &&
      other.name == name &&
      other.key == key &&
      other.agentId == agentId &&
      other.pairedAt == pairedAt &&
      other.lan.join(',') == lan.join(',');
  @override
  int get hashCode => Object.hash(id, name, key, agentId, pairedAt, lan.join(','));
}

enum ComputerRoute { lan, cloud }

/// Sends one sealed blob to this computer through the Escanor cloud and returns the sealed reply. The app implements it with its
/// signed-in API client.
typedef RelayTransport = Future<String> Function({required String agentId, required String deviceId, required String sealed});

/// One WebSocket to a computer's local gateway: text frames in, text frames out.
abstract class LanSocket {
  /// Completes once open; fails if it cannot connect.
  Future<void> get ready;
  Stream<String> get messages;
  void send(String text);
  void close();
}

typedef LanSocketFactory = LanSocket Function(Uri uri);

class _ChannelSocket implements LanSocket {
  _ChannelSocket(Uri uri) : _ch = WebSocketChannel.connect(uri);
  final WebSocketChannel _ch;
  @override
  Future<void> get ready => _ch.ready;
  @override
  Stream<String> get messages => _ch.stream.map((d) => d is String ? d : utf8.decode(d as List<int>));
  @override
  void send(String text) => _ch.sink.add(text);
  @override
  void close() {
    try {
      _ch.sink.close();
    } catch (_) {}
  }
}

LanSocket defaultLanSocket(Uri uri) => _ChannelSocket(uri);

class ClientEnv {
  const ClientEnv({this.client, this.socket, this.relay, this.lanTimeout, this.now});
  final http.Client? client;
  final LanSocketFactory? socket;
  final RelayTransport? relay;
  final Duration? lanTimeout;
  final int Function()? now;
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

final _networkish = RegExp(r'timed out|fetch|network|failed|ECONN|abort', caseSensitive: false);

/// A network failure (try the next address), as opposed to the computer saying no (final). Anything that is not the computer's own
/// words (a socket or HTTP client error) is the network.
bool _isNetworkFailure(Object e) => e is! ComputerError || _networkish.hasMatch(e.message);

/// Pair with a computer using what its QR code (or typed code) says. Tries each local address until one answers.
Future<PairedComputer> pairWithPayload(PairingPayload payload, String deviceName, [ClientEnv env = const ClientEnv()]) async {
  if (payload.v != 1) throw const ComputerError('This pairing code is from a newer version of Escanor. Update the app.');
  final secret = parseCode(payload.code);
  final client = env.client ?? http.Client();
  Object lastError = const ComputerError('This computer could not be reached on the local network.');
  try {
    for (final addr in payload.lan.where(isLocalAddress)) {
      try {
        final got = await phoneRedeem(secret, deviceName, (body) async {
          final res = await withTimeout(
            client.post(Uri.parse('http://$addr/pair'), body: jsonEncode(body.toJson())),
            env.lanTimeout ?? const Duration(seconds: 4),
            'Pairing',
          );
          if (res.statusCode < 200 || res.statusCode >= 300) throw ComputerError(errorOfBody(res.body, 'The computer refused (${res.statusCode}).'));
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          return (deviceId: '${j['deviceId']}', sealedKey: '${j['sealedKey']}');
        });
        return PairedComputer(
          id: got.deviceId,
          name: payload.machine,
          key: B64u.encode(got.key),
          lan: payload.lan,
          agentId: payload.agentId,
          pairedAt: _nowIso(),
        );
      } catch (e) {
        lastError = e;
        // A refusal ("code did not match", "no active pairing") is final; only a network failure moves on to the next address.
        if (!_isNetworkFailure(e)) rethrow;
      }
    }
    throw lastError;
  } finally {
    if (env.client == null) client.close();
  }
}

/// Pair with a computer on the same network knowing only its address (`192.168.1.20` or `192.168.1.20:47625`). No code: the
/// person approves on the computer. `onConfirm` receives the number to check against the one shown there.
Future<PairedComputer> pairByAddress(String address, String deviceName, [LanAskOptions o = const LanAskOptions()]) async {
  final addr = normalizeLanAddress(address);
  if (addr == null) throw const ComputerError('Enter the computer’s address, like 192.168.1.20 (shown on its Phone screen).');
  final client = o.client ?? http.Client();
  try {
    var name = 'My computer';
    try {
      final info = await withTimeout(client.get(Uri.parse('http://$addr/info')), const Duration(seconds: 4), 'The computer');
      final body = jsonDecode(info.body);
      if (body is! Map || body['app'] != 'escanor-desktop') throw const ComputerError('not escanor');
      if (body['name'] != null && '${body['name']}'.isNotEmpty) name = '${body['name']}';
    } catch (_) {
      throw ComputerError(
        'Nothing answered at $addr. Check the address, that your phone is on the same Wi-Fi, and that "On this network" is switched on in Escanor Desktop.',
      );
    }
    final got = await phoneAskLan(
      'http://$addr',
      deviceName,
      LanAskOptions(client: client, onConfirm: o.onConfirm, pollMs: o.pollMs, cancel: o.cancel, now: o.now, sleep: o.sleep),
    );
    return PairedComputer(id: got.deviceId, name: got.machineName ?? name, key: B64u.encode(got.key), lan: [addr], agentId: null, pairedAt: _nowIso());
  } finally {
    if (o.client == null) client.close();
  }
}

final _address = RegExp(r'^([A-Za-z0-9.-]+)(?::(\d{2,5}))?$');

/// `host` or `host:port` (a pasted `http://…/` is fine) as `host:port`, or null. The port defaults to the one the computer uses.
String? normalizeLanAddress(String text) {
  final t = text.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').replaceFirst(RegExp(r'/+$'), '');
  final m = _address.firstMatch(t);
  if (m == null) return null;
  final port = int.parse(m.group(2) ?? '47625');
  if (port > 65535 || !isLocalAddress(m.group(1)!)) return null;
  return '${m.group(1)}:${m.group(2) ?? 47625}';
}

/// A computer of this account that runs Escanor Desktop, as the backend lists it.
class DesktopEntry {
  const DesktopEntry({required this.id, required this.name, required this.online});
  final String id;
  final String name;
  final bool online;
}

/// What the phone needs from the Escanor backend to pair through the cloud. The app implements it with its signed-in API client.
abstract class CloudDirectory {
  /// The computers of this account that run Escanor Desktop, and whether each is online right now.
  Future<List<DesktopEntry>> computers();

  /// Queue a pairing for one computer and return its answer. Fails with the computer's own plain message ("Not this computer.",
  /// "That code did not match.").
  Future<({String deviceId, String sealedKey})> pair(String agentId, {required String sel, required String nonce, required String proof, required String name});
}

/// Pair using only the code: no address, no shared Wi-Fi, so it works from anywhere there is internet. The phone is signed in to
/// the same Escanor account as the computer; it asks each online computer of that account, and only the one showing this code
/// answers. The code itself never leaves the phone (only a proof of it), and the device key comes back sealed under a key derived
/// from it. A scanned QR also names the computer ([agentId]) and its local addresses, which are kept for the "same Wi-Fi" route.
Future<PairedComputer> pairWithCode(String code, String deviceName, CloudDirectory cloud, {String? agentId, String? machine, List<String>? lan}) async {
  final secret = parseCode(code);
  final sel = pairSelector(secret);
  final known = agentId != null && agentId.isNotEmpty
      ? [DesktopEntry(id: agentId, name: machine ?? 'My computer', online: true)]
      : (await cloud.computers()).where((c) => c.online).toList();
  if (known.isEmpty) {
    throw const ComputerError(
      'No computer with Escanor Desktop is online in your account. Open it, sign in to the same account, and turn on "Away from home".',
    );
  }
  for (final target in known) {
    try {
      final got = await phoneRedeem(secret, deviceName, (body) => cloud.pair(target.id, sel: sel, nonce: body.nonce, proof: body.proof, name: body.deviceName));
      return PairedComputer(id: got.deviceId, name: target.name, key: B64u.encode(got.key), lan: lan ?? const [], agentId: target.id, pairedAt: _nowIso());
    } catch (e) {
      if (failureText(e) == 'Not this computer.') continue; // somebody else's code: ask the next one
      rethrow;
    }
  }
  throw const ComputerError('That code is not showing on any of your computers. Check it, and that the computer is signed in to the same account.');
}

class _Pending {
  _Pending(this.match);
  final bool Function(Msg m) match;
  final got = <Msg>[];
  final done = Completer<List<Msg>>();
  Timer? timer;

  /// What a failure becomes (marked as delivered once the request has gone out).
  Object Function(Object e)? onReject;
  void resolve(List<Msg> v) {
    timer?.cancel();
    if (!done.isCompleted) done.complete(v);
  }

  void reject(Object e) {
    timer?.cancel();
    if (!done.isCompleted) done.completeError(onReject?.call(e) ?? e);
  }
}

/// Requests that only read, so sending one again over the cloud after the local link failed cannot do anything twice.
const resendable = {'list', 'pending', 'groups', 'activity', 'ping', 'subscribe'};

/// One live link to one paired computer.
class ComputerClient {
  ComputerClient(this.computer, [this.env = const ClientEnv()]) : _key = B64u.decode(computer.key);

  final PairedComputer computer;
  final ClientEnv env;
  final Uint8List _key;

  LanSocket? _ws;
  StreamSubscription<String>? _sub;
  Uint8List? _sk;
  int _seqIn = 0;
  int _seqOut = 0;
  final _pending = <_Pending>[];
  final _push = <void Function(Msg m)>[];
  final _routeListeners = <void Function(ComputerRoute? r)>[];
  ComputerRoute? _route;
  http.Client? _ownClient;

  http.Client get _http => env.client ?? (_ownClient ??= http.Client());
  Duration get _lanTimeout => env.lanTimeout ?? const Duration(seconds: 3);
  bool get _cloudPossible => env.relay != null && (computer.agentId ?? '').isNotEmpty;

  ComputerRoute? get route => _route;

  void Function() onRoute(void Function(ComputerRoute? r) cb) {
    _routeListeners.add(cb);
    return () => _routeListeners.remove(cb);
  }

  /// Messages the computer pushes on its own: approvals, events, stats. LAN only.
  void Function() onPush(void Function(Msg m) cb) {
    _push.add(cb);
    return () => _push.remove(cb);
  }

  void _setRoute(ComputerRoute? r) {
    if (r != _route) {
      _route = r;
      for (final l in List.of(_routeListeners)) {
        l(r);
      }
    }
  }

  /// Which of this computer's addresses answer right now (as this computer), asked all at once: a dead one costs 1.5 s, not 3 s
  /// each in turn.
  Future<List<String>> _liveAddresses() async {
    Future<String?> probe(String addr) async {
      try {
        final res = await withTimeout(_http.get(Uri.parse('http://$addr/info')), const Duration(milliseconds: 1500), 'probe');
        final body = jsonDecode(res.body);
        return body is Map && body['app'] == 'escanor-desktop' ? addr : null;
      } catch (_) {
        return null;
      }
    }

    final found = await Future.wait(computer.lan.where(isLocalAddress).map(probe));
    return [for (final a in found) ?a];
  }

  Future<ComputerRoute>? _connecting;

  /// Connect the best way available. Completes with the route used; fails if neither works. Requests that arrive together share
  /// one attempt (several sockets opened at once would each replace the last).
  Future<ComputerRoute> connect() => _connecting ??= _connect().whenComplete(() => _connecting = null);

  Future<ComputerRoute> _connect() async {
    for (final addr in await _liveAddresses()) {
      try {
        await withTimeout(_openLan(addr), _lanTimeout, 'The local connection');
        _setRoute(ComputerRoute.lan);
        return ComputerRoute.lan;
      } catch (_) {
        _dropSocket();
      }
    }
    if (_cloudPossible) {
      _setRoute(ComputerRoute.cloud);
      return ComputerRoute.cloud;
    }
    _setRoute(null);
    throw const ComputerError(
      'This computer is not reachable. Check it is on, and that your phone is on the same Wi-Fi (or turn on "Away from home" on the computer).',
    );
  }

  void _dropSocket() {
    final ws = _ws;
    _ws = null;
    _sk = null;
    _sub?.cancel();
    _sub = null;
    try {
      ws?.close();
    } catch (_) {
      // already closed
    }
  }

  Future<void> _openLan(String addr) async {
    final ws = (env.socket ?? defaultLanSocket)(Uri.parse('ws://$addr/session'));
    _ws = ws;
    _seqIn = 0;
    _seqOut = 0;
    final raw = <String>[];
    Completer<void>? wake;
    var closed = false;
    void poke() {
      final w = wake;
      wake = null;
      if (w != null && !w.isCompleted) w.complete();
    }

    void onClosed() {
      closed = true;
      poke();
      if (identical(_ws, ws)) {
        _ws = null;
        _sk = null;
        for (final p in List.of(_pending)) {
          p.reject(const ComputerError('The connection to the computer was closed.'));
        }
        _pending.clear();
        _setRoute(_cloudPossible ? ComputerRoute.cloud : null);
      }
    }

    try {
      await ws.ready;
    } catch (_) {
      throw const ComputerError('connection failed');
    }
    final sub = ws.messages.listen(
      (d) {
        raw.add(d);
        poke();
      },
      onDone: onClosed,
      onError: (_) => onClosed(),
      cancelOnError: true,
    );
    if (identical(_ws, ws)) {
      _sub = sub;
    } else {
      sub.cancel();
      throw const ComputerError('closed');
    }

    Future<Map<String, dynamic>> next() async {
      while (raw.isEmpty) {
        if (closed) throw const ComputerError('closed');
        final w = wake = Completer<void>();
        await w.future;
      }
      return Map<String, dynamic>.from(jsonDecode(raw.removeAt(0)) as Map);
    }

    final nonceC = B64u.encode(randomBytes(16));
    ws.send(jsonEncode({'t': 'hello', 'deviceId': computer.id, 'nonceC': nonceC}));
    final ch = await next();
    final nonceS = '${ch['nonceS']}';
    // Prove it is the real computer: only the holder of the device key can produce this proof.
    Uint8List theirs;
    try {
      theirs = B64u.decode('${ch['proof']}');
    } catch (_) {
      theirs = Uint8List(0);
    }
    if (!timingSafeEqual(serverProof(_key, nonceC, nonceS), theirs)) throw const ComputerError('That is not your computer.');
    ws.send(jsonEncode({'t': 'auth', 'proof': B64u.encode(clientProof(_key, nonceC, nonceS))}));
    final sk = sessionKey(_key, nonceC, nonceS);
    if (!identical(_ws, ws)) throw const ComputerError('closed');
    _sk = sk;
    final aadIn = 'lan:${computer.id}:s2c';

    ({int s, Msg m}) unseal(Map<String, dynamic> f) {
      final j = jsonDecode(utf8.decode(open(sk, '${f['c']}', aadIn))) as Map;
      return (s: (j['s'] as num).toInt(), m: Map<String, dynamic>.from(j['m'] as Map));
    }

    final first = unseal(await next()); // the computer's greeting proves the session works
    if (first.m['t'] != 'hello') throw const ComputerError('Unexpected reply from the computer.');
    _seqIn = first.s;

    // From here on, frames are read as they arrive.
    unawaited(() async {
      try {
        for (;;) {
          final f = unseal(await next());
          if (!identical(_ws, ws)) return;
          if (!(f.s > _seqIn)) continue;
          _seqIn = f.s;
          _deliver(f.m);
        }
      } catch (_) {
        // closed or unauthenticated: the close handler cleans up
      }
    }());
  }

  void _deliver(Msg m) {
    for (final p in List.of(_pending)) {
      if (p.match(m)) {
        p.got.add(m);
        _pending.remove(p);
        p.resolve(p.got);
        return;
      }
    }
    for (final l in List.of(_push)) {
      l(m);
    }
  }

  /// Send a request and collect its replies, over whichever route is live.
  Future<List<Msg>> request(Msg msg, {Duration? timeout}) async {
    if (_route == null) await connect();
    if (_route == ComputerRoute.lan && _ws != null && _sk != null) {
      try {
        return await _requestLan(msg, timeout ?? const Duration(seconds: 60));
      } catch (e) {
        if (!_cloudPossible) rethrow;
        _dropSocket(); // the local link failed mid-request: use the cloud from now on
        _setRoute(ComputerRoute.cloud);
        // A chat or action the computer may already have received is not sent again over the cloud: it could run twice. Only one
        // that never left the phone, or one that only reads, is safe to repeat.
        if (e is ComputerError && e.delivered && !resendable.contains(msg['t'])) rethrow;
      }
    }
    return _requestCloud(msg);
  }

  Future<List<Msg>> _requestLan(Msg msg, Duration timeout) {
    final id = msg['id'] is String ? msg['id'] as String : null;
    final type = msg['t'];
    // replies carry the request id (call, chat); the rest are matched by their type
    final p = _Pending(
      (m) => id != null
          ? ((m['t'] == 'result' || m['t'] == 'reply' || m['t'] == 'error') && m['id'] == id)
          : (type == 'list' && m['t'] == 'capabilities') ||
                (type == 'pending' && m['t'] == 'pending') ||
                (type == 'ping' && m['t'] == 'pong') ||
                // matched by type too (the TypeScript client leaves these to time out; the computer answers them by type)
                (type == 'groups' && (m['t'] == 'groups' || (m['t'] == 'error' && m['id'] == null))) ||
                (type == 'request_group' && (m['t'] == 'group_request' || (m['t'] == 'error' && m['id'] == null))) ||
                (type == 'activity' && (m['t'] == 'activity' || (m['t'] == 'error' && m['id'] == null))),
    );
    var delivered = false;
    // Failing after the message went out (the link dropped while waiting) is marked so the caller does not send it again.
    p.onReject = (e) => delivered ? ComputerError(failureText(e), delivered: true) : e;
    p.timer = Timer(timeout, () {
      _pending.remove(p);
      p.reject(const ComputerError('The computer did not answer in time.'));
    });
    if (type == 'approve' || type == 'subscribe') {
      // no reply expected
      _sendLan(msg).then((_) => p.resolve(const []), onError: p.reject);
      return p.done.future;
    }
    _pending.add(p);
    _sendLan(msg).then((_) => delivered = true, onError: (Object e) {
      _pending.remove(p);
      p.reject(e);
    });
    return p.done.future;
  }

  Future<void> _sendLan(Msg msg) async {
    final ws = _ws, sk = _sk;
    if (ws == null || sk == null) throw const ComputerError('Not connected.');
    _seqOut += 1;
    ws.send(
      jsonEncode({
        'c': seal(sk, jsonEncode({'s': _seqOut, 'm': msg}), 'lan:${computer.id}:c2s'),
      }),
    );
  }

  Future<List<Msg>> _requestCloud(Msg msg) async {
    final relay = env.relay;
    final agentId = computer.agentId;
    if (relay == null || agentId == null || agentId.isEmpty) throw const ComputerError('This computer is not reachable from here.');
    int now() => env.now?.call() ?? DateTime.now().millisecondsSinceEpoch;
    final req = sealRelayRequest(computer.id, _key, msg, now: now());
    final reply = await relay(agentId: agentId, deviceId: computer.id, sealed: req.sealed);
    return openRelayResponse(computer.id, _key, reply, req.id, now: now());
  }

  /// Ask for live events and stats. Only the local route can push, so over the cloud this is a no-op.
  Future<void> subscribe(List<String> channels) async {
    if (_route == ComputerRoute.lan) await request(ClientMsg.subscribe(channels));
  }

  void close() {
    _dropSocket();
    for (final p in List.of(_pending)) {
      p.reject(const ComputerError('Closed.'));
    }
    _pending.clear();
    _setRoute(null);
    _ownClient?.close();
    _ownClient = null;
  }
}
