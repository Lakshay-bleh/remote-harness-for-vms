/// A way to call off something that is under way (listening, waiting for an answer): the Dart side of the web's AbortSignal. Pure.
library;

class VoiceCancel {
  bool _aborted = false;
  final List<void Function()> _listeners = [];

  bool get aborted => _aborted;

  void abort() {
    if (_aborted) return;
    _aborted = true;
    final ls = List.of(_listeners);
    _listeners.clear();
    for (final l in ls) {
      l();
    }
  }

  /// Run [fn] when this is aborted (at once if it already is). Returns how to stop listening.
  void Function() onAbort(void Function() fn) {
    if (_aborted) {
      fn();
      return () {};
    }
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }
}
