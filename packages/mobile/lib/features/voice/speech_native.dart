import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'cancel.dart';
import 'speech.dart';

/// The phone's speech recogniser (speech_to_text: Android's SpeechRecognizer, Apple's Speech framework) and voice (flutter_tts),
/// behind the small [SpeechPlugin] interface the listening logic is tested with.

bool get _isPhone {
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// speech_to_text shaped like the recogniser [listenOnce] expects. One for the app: the recogniser is one per phone.
class NativeSpeech implements SpeechPlugin {
  NativeSpeech._();
  static final NativeSpeech instance = NativeSpeech._();

  final SpeechToText _stt = SpeechToText();
  final Map<String, Set<void Function(Map<String, Object?>)>> _handlers = {};
  bool _ready = false;

  void _emit(String name, Map<String, Object?> e) {
    for (final h in List.of(_handlers[name] ?? const <void Function(Map<String, Object?>)>{})) {
      h(e);
    }
  }

  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) _emit('listeningState', {'state': 'started'});
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _emit('listeningState', {'state': 'stopped'});
  }

  void _onError(SpeechRecognitionError e) {
    // Nothing said, or nothing that matched: that is silence, not a failure.
    if (e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout') {
      _emit('listeningState', {'state': 'stopped'});
      return;
    }
    _emit('error', {'message': _errorWords(e.errorMsg)});
  }

  static String _errorWords(String code) => switch (code) {
        'error_audio_error' || 'error_audio' => 'The microphone could not be used.',
        'error_permission' || 'error_insufficient_permissions' => 'The microphone is not allowed for Escanor.',
        'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' => 'Speech recognition needs a connection right now.',
        'error_busy' || 'error_recognizer_busy' => 'The speech recogniser is busy. Try again.',
        'error_language_not_supported' || 'error_language_unavailable' => 'Speech recognition for English is not installed on this phone.',
        _ => 'Speech recognition failed.',
      };

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> start(Map<String, Object?> options) async {
    if (!await init()) throw SpeechError('Speech recognition is not available here.');
    // Another part of the app may have set its own listeners on the shared recogniser: these are the ones for this listen.
    _stt.errorListener = _onError;
    _stt.statusListener = _onStatus;
    final silence = (options['allowForSilence'] as int?) ?? 1500;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => _emit('partialResults', {
        'matches': [r.recognizedWords],
      }),
      listenOptions: SpeechListenOptions(
        partialResults: options['partialResults'] != false,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        pauseFor: Duration(milliseconds: silence < 1000 ? 1000 : silence + 500),
        listenFor: const Duration(seconds: 60),
        localeId: ((options['language'] as String?) ?? 'en-US').replaceAll('-', '_'),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<SpeechSubscription> addListener(String event, void Function(Map<String, Object?> e) fn) async {
    (_handlers[event] ??= {}).add(fn);
    return SpeechSubscription(() async => _handlers[event]?.remove(fn));
  }
}

/// Ask for the microphone (the phone shows its own prompt the first time).
Future<MicState> ensureMic() async {
  if (!_isPhone) return MicState.unsupported;
  try {
    var mic = await Permission.microphone.status;
    if (!mic.isGranted) mic = await Permission.microphone.request();
    if (!mic.isGranted) return MicState.denied;
    if (Platform.isIOS) {
      var speech = await Permission.speech.status;
      if (!speech.isGranted) speech = await Permission.speech.request();
      if (!speech.isGranted) return MicState.denied;
    }
    return await NativeSpeech.instance.init() ? MicState.granted : MicState.unsupported;
  } catch (_) {
    return MicState.unsupported;
  }
}

/// Listen for one sentence with the phone's recogniser.
Future<String> listen({void Function(String text)? onPartial, VoiceCancel? cancel, Duration timeout = const Duration(seconds: 15)}) {
  if (!_isPhone) return Future.error(SpeechError('Speech recognition is not available here.'));
  return listenOnce(NativeSpeech.instance, onPartial: onPartial, cancel: cancel, timeout: timeout);
}

/// True where the person can talk to Escanor at all.
bool canListen() => _isPhone;

FlutterTts? _tts;

Future<FlutterTts> _voice() async {
  final existing = _tts;
  if (existing != null) return existing;
  final t = FlutterTts();
  try {
    await t.awaitSpeakCompletion(true);
    await t.setLanguage('en-US');
    if (Platform.isIOS) {
      // Speak through the loudspeaker even though the microphone was just in use.
      await t.setSharedInstance(true);
      await t.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      ]);
    }
  } catch (_) {
    // a phone without a voice: speaking quietly does nothing
  }
  return _tts = t;
}

/// Say something out loud. Resolves when it has finished (or at once where the phone cannot speak).
Future<void> speak(String text) async {
  if (text.trim().isEmpty || !_isPhone) return;
  try {
    final t = await _voice();
    await t.speak(text.length > 600 ? text.substring(0, 600) : text);
  } catch (_) {
    // no voice installed or interrupted: the reply is still on screen
  }
}

Future<void> stopSpeaking() async {
  if (!_isPhone) return;
  try {
    await (await _voice()).stop();
  } catch (_) {}
}

/// Speak instead of type, for a message box: the words appear as they are heard, and the person can fix them before sending.
/// Tapping again stops. What was already in the box stays. (The web app's useDictation.)
class Dictation {
  Dictation(this.onText, {this.onChange});

  /// Called with the whole message (what was typed, then what is heard) as it changes.
  final void Function(String text) onText;

  /// Called when [listening] or [error] changes.
  final void Function()? onChange;

  bool listening = false;
  String? error;
  VoiceCancel? _cancel;

  bool get supported => canListen();

  void stop() => _cancel?.abort();

  Future<void> start(String current) async {
    error = null;
    onChange?.call();
    final mic = await ensureMic();
    if (mic != MicState.granted) {
      error = mic == MicState.denied
          ? (Platform.isIOS
              ? 'Allow the microphone in iPhone Settings, under Escanor.'
              : 'Allow the microphone in Android Settings, under Apps, Escanor, Permissions.')
          : 'Speaking needs the Escanor Android app, or a browser that can listen (Chrome or Safari).';
      onChange?.call();
      return;
    }
    final c = VoiceCancel();
    _cancel = c;
    listening = true;
    onChange?.call();
    try {
      final said = await listen(cancel: c, timeout: const Duration(seconds: 60), onPartial: (t) => onText(joinSpoken(current, t)));
      if (said.isNotEmpty) onText(joinSpoken(current, said));
    } catch (e) {
      final m = e is SpeechError ? e.message : '';
      error = m.isNotEmpty ? m : 'I could not hear you.';
    } finally {
      if (identical(_cancel, c)) _cancel = null;
      listening = false;
      onChange?.call();
    }
  }

  void toggle(String current) => _cancel != null ? stop() : start(current);

  void dispose() => _cancel?.abort();
}
