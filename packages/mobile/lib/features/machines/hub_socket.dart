import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'hub_url.dart';
import 'protocol.dart';

typedef SocketConnector = WebSocketChannel Function(Uri uri, List<String> protocols);

WebSocketChannel _defaultConnector(Uri uri, List<String> protocols) => WebSocketChannel.connect(uri, protocols: protocols);

/// The hub's push channel (ws.ts): machines coming and going, chat messages as they stream, permission prompts.
/// Reconnects on its own with a growing delay; a socket that was stopped (sign-out, a new login) never delivers
/// another event, so one person's chats cannot reach the next.
class HubSocket {
  HubSocket({SocketConnector? connector, required this.token, required this.hubUrl, Duration Function(int attempt)? backoff})
      : _connector = connector ?? _defaultConnector,
        _backoff = backoff ?? reconnectDelay;

  final SocketConnector _connector;
  final String? Function() token;
  final String Function() hubUrl;
  final Duration Function(int attempt) _backoff;

  /// Called after a dropped connection is back (events may have been missed while it was down).
  void Function()? onReconnected;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  final Set<void Function(HubEvent)> _handlers = {};
  bool _stopped = false;
  Timer? _ping;
  Timer? _retry;
  Timer? _guard;
  int _attempt = 0;
  bool _everOpened = false;

  /// Keeps the connection alive through Cloudflare's idle timeout; the hub answers 'pong' itself.
  static const pingEvery = Duration(seconds: 20);

  /// A connection that has said nothing, not even a 'pong', for this long is dead even if the phone has not noticed
  /// (it changed network, or slept): it is replaced.
  static const deadAfter = Duration(seconds: 50);

  static const connectTimeout = Duration(seconds: 15);

  DateTime _lastFrame = DateTime.now();
  DateTime Function() _now = DateTime.now;

  /// For tests: a clock they control.
  set clock(DateTime Function() now) => _now = now;

  bool get connected => _ws != null;

  /// How long since anything (a message, or the hub's 'pong') was heard on the open connection.
  Duration quietSince(DateTime now) => now.difference(_lastFrame);

  void connect() {
    _stopped = false;
    _retry?.cancel();
    _retry = null;
    if (_ws != null) return;
    final t = token();
    final hub = hubUrl();
    if (t == null || t.isEmpty || hub.isEmpty) return;
    final Uri uri;
    try {
      uri = socketUrl(hub);
    } catch (_) {
      return; // never anything but wss
    }
    final WebSocketChannel ws;
    try {
      ws = _connector(uri, socketProtocols(t));
    } catch (_) {
      _scheduleRetry();
      return;
    }
    _ws = ws;
    // An attempt that never completes (no network) must not hold the slot forever.
    _guard?.cancel();
    final guard = _guard = Timer(connectTimeout, () {
      if (_ws != ws || _stopped) return;
      _ping?.cancel();
      _ping = null;
      _sub?.cancel();
      _sub = null;
      _ws = null;
      try {
        ws.sink.close();
      } catch (_) {}
      _scheduleRetry();
    });
    ws.ready.then((_) {
      guard.cancel();
      if (_stopped || _ws != ws) return;
      final reconnected = _everOpened;
      _everOpened = true;
      _attempt = 0;
      _lastFrame = _now();
      _ping?.cancel();
      _ping = Timer.periodic(pingEvery, (_) {
        if (_ws != ws) return;
        if (_now().difference(_lastFrame) > deadAfter) {
          _drop(ws);
          return;
        }
        try {
          ws.sink.add('ping');
        } catch (_) {}
      });
      if (reconnected) onReconnected?.call();
    }, onError: (_) => guard.cancel());
    _sub = ws.stream.listen(
      (data) {
        if (_stopped || _ws != ws) return;
        _lastFrame = _now();
        final msg = parseHubFrame(data);
        if (msg == null) return; // 'pong', malformed frames, types from a newer hub
        for (final h in List.of(_handlers)) {
          h(msg);
        }
      },
      onError: (_) {},
      onDone: () {
        guard.cancel();
        if (_ws != ws) return;
        _ping?.cancel();
        _ping = null;
        _ws = null;
        _sub = null;
        if (!_stopped) _scheduleRetry();
      },
      cancelOnError: false,
    );
  }

  /// Throw this connection away and open a new one now.
  void _drop(WebSocketChannel ws) {
    if (_ws != ws) return;
    _guard?.cancel();
    _guard = null;
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    _ws = null;
    try {
      ws.sink.close();
    } catch (_) {}
    if (!_stopped) {
      _attempt = 0;
      connect();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final delay = _backoff(_attempt++);
    _retry = Timer(delay, () {
      _retry = null;
      if (!_stopped) connect();
    });
  }

  /// Back in the foreground: try again now rather than at the end of a long wait.
  void wake() {
    if (_stopped || _ws != null) return;
    _attempt = 0;
    connect();
  }

  /// Back in the foreground, or the network changed: whatever connection there is may be dead without saying so, so
  /// replace it. Listeners are told it is back (see [onReconnected]) so they can fetch what they missed.
  void reconnect() {
    if (_stopped) return;
    final ws = _ws;
    if (ws == null) {
      wake();
      return;
    }
    _drop(ws);
  }

  /// Returns the function that unsubscribes.
  void Function() subscribe(void Function(HubEvent) handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  void stop() {
    _stopped = true;
    _guard?.cancel();
    _guard = null;
    _ping?.cancel();
    _ping = null;
    _retry?.cancel();
    _retry = null;
    final ws = _ws;
    _ws = null;
    _sub?.cancel();
    _sub = null;
    _attempt = 0;
    _everOpened = false;
    try {
      ws?.sink.close();
    } catch (_) {}
  }
}
