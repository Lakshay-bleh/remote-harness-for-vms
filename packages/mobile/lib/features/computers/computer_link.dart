// ignore_for_file: prefer_initializing_formals (a private field set from a named parameter)
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'link.dart';
import 'protocol/client.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';

enum LinkState { connecting, online, offline }

/// A live link to one paired computer (the port of `useComputer`): connects the best way available, checks the computer really
/// answers, and keeps trying again by itself when it does not. A single failed request is not "offline" (it takes two in a row),
/// and an offline computer is retried with a growing pause, and when the app returns to the foreground.
class ComputerLink extends ChangeNotifier with WidgetsBindingObserver {
  /// [relay] null is the person's "Wi-Fi only" choice for this computer: only the local route exists.
  ComputerLink(PairedComputer computer, {RelayTransport? relay, ClientEnv env = const ClientEnv(), this.makeClient}) : _env = env {
    WidgetsBinding.instance.addObserver(this);
    _use(computer, relay);
  }

  /// Tests: build the client some other way.
  final ComputerClient Function(PairedComputer c, ClientEnv env)? makeClient;
  final ClientEnv _env;

  ComputerClient? _client;
  void Function()? _offRoute;
  void Function()? _offPush;

  LinkState state = LinkState.connecting;
  ComputerRoute? route;
  String? error;

  /// Failed connects in a row; 0 once connected.
  int attempt = 0;
  int _failures = 0;
  Timer? _retry;
  bool _disposed = false;
  final _pushListeners = <void Function(Msg m)>[];

  /// Connect to [computer] with [relay] (the computer, or its route preference, changed).
  void use(PairedComputer computer, RelayTransport? relay) => _use(computer, relay);

  void _use(PairedComputer computer, RelayTransport? relay) {
    _teardown();
    final env = ClientEnv(client: _env.client, socket: _env.socket, relay: relay, lanTimeout: _env.lanTimeout, now: _env.now);
    final client = makeClient?.call(computer, env) ?? ComputerClient(computer, env);
    _client = client;
    _failures = 0;
    attempt = 0;
    _offRoute = client.onRoute((r) {
      route = r;
      _notify();
    });
    _offPush = client.onPush((m) {
      for (final l in List.of(_pushListeners)) {
        l(m);
      }
    });
    unawaited(connect());
  }

  void _teardown() {
    _retry?.cancel();
    _offRoute?.call();
    _offPush?.call();
    _client?.close();
    _client = null;
  }

  Future<void> connect({bool quiet = false}) async {
    final client = _client;
    if (client == null) return;
    _retry?.cancel();
    if (!quiet) {
      state = LinkState.connecting;
      _notify();
    }
    try {
      final used = await client.connect();
      // The cloud route is "connected" as soon as it is available, which says nothing about the computer: ask it something.
      if (used == ComputerRoute.cloud) await client.request(ClientMsg.ping(), timeout: const Duration(seconds: 40));
      if (!identical(_client, client)) return;
      _failures = 0;
      attempt = 0;
      error = null;
      state = LinkState.online;
      _notify();
      await client.subscribe(['events']).catchError((_) {});
    } catch (e) {
      if (!identical(_client, client)) return;
      state = LinkState.offline;
      error = offlineMessage(e, client.route);
      attempt += 1;
      _notify();
      _scheduleRetry();
    }
  }

  /// Offline: try again after a pause that grows.
  void _scheduleRetry() {
    _retry?.cancel();
    if (_disposed || state != LinkState.offline) return;
    _retry = Timer(Duration(milliseconds: retryDelayMs(attempt)), () => connect(quiet: true));
  }

  void reconnect() => unawaited(connect());

  /// Send one request. Two failures in a row count as offline (and start the retries).
  Future<List<Msg>> request(Msg msg, {Duration? timeout}) async {
    final client = _client;
    if (client == null) throw const ComputerError('Not connected.');
    try {
      // A chat can take a while on the computer; give it as long over Wi-Fi as the cloud route allows (a timed-out chat is not resent).
      final out = await client.request(msg, timeout: timeout ?? (msg['t'] == 'chat' ? const Duration(seconds: 120) : null));
      _failures = 0;
      if (state != LinkState.online && identical(_client, client)) {
        state = LinkState.online;
        _notify();
      }
      return out;
    } catch (e) {
      _failures += 1;
      if (shouldShowOffline(_failures) && identical(_client, client)) {
        state = LinkState.offline;
        error = offlineMessage(e, client.route);
        _notify();
        _scheduleRetry();
      }
      rethrow;
    }
  }

  void Function() onPush(void Function(Msg m) cb) {
    _pushListeners.add(cb);
    return () => _pushListeners.remove(cb);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Brought back to the foreground (often on another network): try straight away.
    if (state == AppLifecycleState.resumed && this.state == LinkState.offline) unawaited(connect(quiet: true));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    super.dispose();
  }
}
