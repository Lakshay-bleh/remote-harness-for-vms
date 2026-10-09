import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'busy.dart';
import 'cache.dart';

/// Load something now, again every [every] (null = never), and again whenever the app comes back to the
/// foreground. The port of the web app's `useLoad`.
///
/// With a [cache], what was loaded last time is shown at once and only asked for again when older than
/// its time to live; [reload] always asks. [decode] turns the cached JSON back into a T (and [encode]
/// turns a T into JSON); without them T must itself be JSON (maps/lists).
class Loader<T> extends ChangeNotifier with WidgetsBindingObserver {
  Loader(this._load, {this.every, this.cache, this.decode, this.encode, bool start = true}) {
    final hit = cache == null ? null : readCache(cache!);
    if (hit != null) {
      try {
        data = decode != null ? decode!(hit.value) : hit.value as T;
        stale = !hit.fresh;
        loading = false;
      } catch (_) {}
    }
    WidgetsBinding.instance.addObserver(this);
    if (start) _run(force: false);
  }

  Future<T> Function() _load;
  final Duration? every;
  final CachePolicy? cache;
  final T Function(Object? json)? decode;
  final Object? Function(T value)? encode;

  T? data;
  String? error;

  /// True only while there is nothing to show yet.
  bool loading = true;

  /// True while a fresh answer is on its way.
  bool refreshing = false;

  /// The data on screen is the remembered copy, not yet confirmed.
  bool stale = false;

  Timer? _timer;
  bool _disposed = false;
  int _generation = 0;

  /// Swap what is loaded (another computer, another page) and load it.
  void replace(Future<T> Function() load) {
    _load = load;
    _generation++;
    reload();
  }

  void reload() => _run(force: true);

  Future<void> _run({required bool force}) async {
    _timer?.cancel();
    final hit = cache == null ? null : readCache(cache!);
    if (hit != null && hit.fresh && !force && every == null && data != null) {
      loading = false;
      stale = false;
      _notify();
      return;
    }
    final gen = _generation;
    refreshing = true;
    _notify();
    try {
      final next = await trackBusy(_load());
      if (_disposed || gen != _generation) return;
      if (cache != null) writeCache(cache!.key, encode != null ? encode!(next) : next);
      data = next;
      stale = false;
      error = null;
    } on SessionEnded {
      // the session notifier already sent the person to sign-in
    } catch (e) {
      if (_disposed || gen != _generation) return;
      error = errorText(e);
    } finally {
      if (!_disposed && gen == _generation) {
        loading = false;
        refreshing = false;
        _notify();
        if (every != null) _timer = Timer(every!, () => _run(force: true));
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
