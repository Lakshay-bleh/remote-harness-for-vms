import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'spoken.dart';

/// Speak instead of type: the words appear in the message box as they are heard, and the person can fix them before sending.
/// Tapping again stops. What was already in the box stays. (The web app's voice/useDictation.)
class Dictation extends ChangeNotifier {
  Dictation(this.onText);

  /// Everything in the box: what was typed before, then what has been heard so far.
  final void Function(String text) onText;

  final SpeechToText _speech = SpeechToText();

  bool listening = false;
  String? error;

  /// False once the phone has said it cannot recognise speech at all.
  bool supported = true;

  int _session = 0;
  bool _disposed = false;

  void toggle(String current) => listening ? stop() : start(current);

  Future<void> start(String current) async {
    error = null;
    final session = ++_session;
    bool ok;
    try {
      ok = await _speech.initialize(onError: _onError, onStatus: _onStatus);
    } catch (_) {
      ok = false;
    }
    if (_disposed || session != _session) return;
    // The recogniser is shared with voice mode: make sure what it says now comes here.
    _speech.errorListener = _onError;
    _speech.statusListener = _onStatus;
    if (!ok) {
      bool permitted = false;
      try {
        permitted = await _speech.hasPermission;
      } catch (_) {}
      if (!permitted) {
        error = micProblem(denied: true, ios: _isIos);
      } else {
        supported = false;
        error = micProblem(denied: false, ios: _isIos);
      }
      _notify();
      return;
    }
    listening = true;
    _notify();
    try {
      await _speech.listen(
        onResult: (r) {
          if (session != _session || _disposed) return;
          if (r.recognizedWords.isNotEmpty) onText(joinSpoken(current, r.recognizedWords));
          if (r.finalResult) _finish(session);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (session != _session) return;
      error = 'I could not hear you.';
      _finish(session);
    }
  }

  void stop() {
    _session++;
    try {
      _speech.stop();
    } catch (_) {}
    if (listening) {
      listening = false;
      _notify();
    }
  }

  void _finish(int session) {
    if (session != _session) return;
    if (listening) {
      listening = false;
      _notify();
    }
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _finish(_session);
  }

  void _onError(SpeechRecognitionError e) {
    final m = e.errorMsg;
    // Hearing nothing is not a problem worth a message.
    if (m.contains('no_match') || m.contains('speech_timeout')) {
      _finish(_session);
      return;
    }
    if (m.contains('permission')) {
      error = micProblem(denied: true, ios: _isIos);
    } else if (m.contains('network')) {
      error = 'Speech recognition needs a connection right now. Try again when you are online.';
    } else {
      error = 'I could not hear you.';
    }
    _finish(_session);
    _notify();
  }

  bool get _isIos {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (listening) {
      try {
        _speech.cancel();
      } catch (_) {}
    }
    super.dispose();
  }
}
