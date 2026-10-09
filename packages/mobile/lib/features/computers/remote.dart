// ignore_for_file: prefer_initializing_formals (a private field set from a named parameter)
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/busy.dart';
import '../../core/cache.dart';
import 'protocol/failure.dart';

/// How long to wait before trying again after a failure, or null when it is time to stop and say so.
Duration? retryDelay(int attempt) => const [Duration(milliseconds: 1500), Duration(milliseconds: 4000), Duration(milliseconds: 9000)].elementAtOrNull(attempt);

/// [f], or a failure after [d]: a request over the cloud can otherwise wait for minutes.
Future<T> withDeadline<T>(Future<T> f, Duration d, [String message = 'The computer took too long to answer.']) =>
    f.timeout(d, onTimeout: () => throw ComputerError(message));

/// Ask one of the computer's screens' questions the way a phone app should (the port of `useRemote`): show what was remembered at
/// once, ask once at a time, try again by itself a few times when the first try fails, and never leave the person with a spinner
/// that does not end. A failure is only an error when there is nothing remembered to show instead.
///
/// Values are remembered as JSON: [decode] reads the cached copy back and [encode] writes it.
class Remote<T> extends ChangeNotifier with WidgetsBindingObserver {
  Remote({
    required this.computerId,
    required this.what,
    required this.run,
    required this.ttl,
    required this.decode,
    required this.encode,
    this.every,
    this.deadline = const Duration(seconds: 30),
    bool online = false,
  }) : _online = online {
    final hit = readCache(_policy);
    if (hit != null) {
      try {
        data = decode(hit.value);
        stale = !hit.fresh;
      } catch (_) {}
    }
    WidgetsBinding.instance.addObserver(this);
    _restart();
  }

  final String computerId;

  /// What is being asked for: part of the cache key ("groups", "activity", "stats").
  final String what;
  Future<T> Function() run;

  /// Trusted without asking again for this long.
  final Duration ttl;

  /// Ask again this often while the screen is showing (counted from the end of the last answer).
  Duration? every;

  /// Longest to wait for one answer.
  final Duration deadline;
  final T Function(Object? json) decode;
  final Object? Function(T value) encode;

  T? data;

  /// Why the last try failed (shown only when there is nothing else to show).
  Object? error;

  /// An answer is on its way.
  bool refreshing = false;

  /// What is on screen was remembered from an earlier visit and is being checked.
  bool stale = false;

  /// Nothing to show yet.
  bool get loading => data == null && (refreshing || error == null);

  bool _online;
  bool _enabled = true;
  bool _busy = false;
  bool _forced = false;
  bool _hidden = false;
  bool _disposed = false;
  int _generation = 0;
  int _attempt = 0;
  Timer? _timer;

  String get _key => 'computer:$computerId:$what';
  CachePolicy get _policy => CachePolicy(_key, ttl: ttl, maxAge: const Duration(days: 7));

  bool get _active => _online && _enabled;

  /// Only ask while the computer is reachable.
  set online(bool v) {
    if (v == _online) return;
    _online = v;
    _restart();
  }

  /// Turn this off while the screen is not showing.
  set enabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    _restart();
  }

  void _restart() {
    _generation++;
    _timer?.cancel();
    _attempt = 0;
    _busy = false;
    if (_active) _tick(_generation);
  }

  Future<void> _tick(int gen) async {
    if (_disposed || gen != _generation || _busy || !_active) return;
    final force = _forced;
    _forced = false;
    final hit = readCache(_policy);
    if (hit != null && hit.fresh && !force && every == null) {
      try {
        data = decode(hit.value);
        stale = false;
        _notify();
        return;
      } catch (_) {}
    }
    if (_hidden && !force) {
      _timer = Timer(const Duration(seconds: 2), () => _tick(gen));
      return;
    }
    _busy = true;
    refreshing = true;
    _notify();
    try {
      final next = await trackBusy(withDeadline(run(), deadline));
      writeCache(_key, encode(next));
      if (_disposed || gen != _generation) return;
      data = next;
      stale = false;
      error = null;
      _attempt = 0;
      if (every != null) _timer = Timer(every!, () => _tick(gen));
    } catch (e) {
      if (_disposed || gen != _generation) return;
      error = e;
      final wait = retryDelay(_attempt++);
      if (wait != null) {
        _timer = Timer(wait, () => _tick(gen));
      } else if (every != null) {
        _timer = Timer(every! * 2, () => _tick(gen));
      }
    } finally {
      if (gen == _generation) _busy = false;
      if (!_disposed && gen == _generation) {
        refreshing = false;
        _notify();
      }
    }
  }

  void reload() {
    _forced = true;
    error = null;
    _restart();
  }

  /// Replace what is shown (after something was changed) and remember it.
  void set(T v) {
    writeCache(_key, encode(v));
    data = v;
    stale = false;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _hidden = state != AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && _active) {
      _timer?.cancel();
      _restart();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
