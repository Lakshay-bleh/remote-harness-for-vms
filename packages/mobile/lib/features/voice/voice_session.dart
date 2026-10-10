import 'dart:async';

import 'package:flutter/foundation.dart';

import '../computers/computer_api.dart';
import 'actions.dart';
import 'assistant.dart';
import 'assistant_answer.dart';
import 'cancel.dart';
import 'commands.dart';
import 'device.dart';
import 'resolve.dart';
import 'speech.dart';
import 'speech_native.dart' as native;
import 'voice_prefs.dart';

enum VoicePhase { idle, listening, thinking, speaking }

/// How one turn ended, so a conversation can decide whether to listen again.
enum TurnOutcome { spoke, silent, stop, cancelled, error }

/// Hand a sentence to the Escanor assistant and wait for its answer (null/empty when it only started working).
typedef OnAssistant = Future<String?> Function(String text, VoiceCancel cancel);

/// Do what was said: the real one asks the phone, the computer, the server and the assistant (see [voiceHandler]).
typedef VoiceHandler = Future<Reply> Function(String said, {required void Function(String text) interim, required VoiceCancel cancel});

/// What a turn uses from the phone, replaceable in tests.
class VoiceIo {
  const VoiceIo({
    this.ensureMic = native.ensureMic,
    this.listen = _listen,
    this.speak = native.speak,
    this.stopSpeaking = native.stopSpeaking,
    this.ios = _ios,
  });
  final Future<MicState> Function() ensureMic;
  final Future<String> Function({void Function(String text)? onPartial, VoiceCancel? cancel}) listen;
  final Future<void> Function(String text) speak;
  final Future<void> Function() stopSpeaking;
  final bool Function() ios;
}

Future<String> _listen({void Function(String text)? onPartial, VoiceCancel? cancel}) => native.listen(onPartial: onPartial, cancel: cancel);
bool _ios() => isIOS;

/// The real [VoiceHandler]: everything Escanor's voice can reach.
VoiceHandler voiceHandler({required void Function(VoiceTab tab) go, required OnAssistant onAssistant}) {
  return (said, {required interim, required cancel}) {
    final computers = loadComputers();
    final dev = deviceOrNull();
    return handleUtterance(
      said,
      AssistantDeps(
        device: dev,
        hasComputer: computers.isNotEmpty,
        toComputer: (text) => chatWithComputer(computers.first, text),
        toAssistant: (text) => onAssistant(text, cancel),
        go: go,
        phone: PhoneOptions(directCalls: getVoicePrefs().directCalls),
        ack: (t) => native.speak(forSpeech(t)),
        interim: interim,
        resolve: (text) => resolveOnServer(text, dev),
      ),
    );
  };
}

/// One conversation turn with Escanor: listen, understand, do it, say what happened. [start] runs a whole turn; [cancel] stops
/// listening or talking at once. (The web app's useVoiceSession.)
class VoiceSession extends ChangeNotifier {
  VoiceSession({required this.handle, this.io = const VoiceIo()});

  final VoiceHandler handle;
  final VoiceIo io;

  VoicePhase phase = VoicePhase.idle;
  String heard = '';
  Reply? reply;

  VoiceCancel? _abort;
  int _turn = 0;
  bool _disposed = false;

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _turn += 1;
    _abort?.abort();
    io.stopSpeaking();
    _set(() => phase = VoicePhase.idle);
  }

  Future<TurnOutcome> start() async {
    cancel();
    final mine = _turn;
    bool alive() => _turn == mine && !_disposed;
    _set(() {
      heard = '';
      reply = null;
    });

    final mic = await io.ensureMic();
    if (!alive()) return TurnOutcome.cancelled;
    if (mic != MicState.granted) {
      _set(() => reply = Reply(
            ok: false,
            say: mic == MicState.denied
                ? 'I need the microphone. ${io.ios() ? 'In iPhone Settings, open Escanor and allow the microphone.' : 'In Android Settings, open Apps, then Escanor, then Permissions, and allow the microphone.'}'
                : 'Voice needs speech recognition, and this phone does not offer it. ${io.ios() ? 'Check that Siri and Dictation are allowed in iPhone Settings.' : 'Install or turn on Google speech services in Android Settings.'}',
          ));
      return TurnOutcome.error;
    }

    final abort = VoiceCancel();
    _abort = abort;
    _set(() => phase = VoicePhase.listening);
    String said;
    try {
      said = await io.listen(
        onPartial: (t) {
          if (alive()) _set(() => heard = t);
        },
        cancel: abort,
      );
    } catch (e) {
      if (alive()) {
        final why = e is SpeechError ? e.message : '';
        final where = io.ios()
            ? 'Check the microphone permission in iPhone Settings, under Escanor.'
            : 'Check the microphone permission in Android Settings, under Apps, Escanor.';
        _set(() {
          reply = Reply(ok: false, say: 'I couldn’t hear you. $why $where'.replaceAll(RegExp(r'\s+'), ' ').trim());
          phase = VoicePhase.idle;
        });
      }
      return alive() ? TurnOutcome.error : TurnOutcome.cancelled;
    }
    if (!alive()) return TurnOutcome.cancelled;
    if (said.trim().isEmpty) {
      _set(() => phase = VoicePhase.idle);
      return TurnOutcome.silent;
    }
    _set(() {
      heard = said;
      phase = VoicePhase.thinking;
    });

    final r = await handle(said, interim: (t) {
      if (alive()) _set(() => reply = Reply(ok: true, say: t));
    }, cancel: abort);
    if (!alive()) return TurnOutcome.cancelled;
    _set(() {
      reply = r;
      phase = VoicePhase.speaking;
    });
    await io.speak(forSpeech(r.say));
    if (!alive()) return TurnOutcome.cancelled;
    _set(() => phase = VoicePhase.idle);
    return r.kind == ReplyKind.stop ? TurnOutcome.stop : TurnOutcome.spoke;
  }

  @override
  void dispose() {
    _disposed = true;
    _turn += 1;
    _abort?.abort();
    io.stopSpeaking();
    super.dispose();
  }
}

/// Voice mode: open, a conversation that keeps listening after each answer until the person is done, closed.
class VoiceConversation extends ChangeNotifier {
  VoiceConversation(this.session, {this.pause = const Duration(milliseconds: 250), this.onOpenChanged});

  final VoiceSession session;
  final Duration pause;

  /// The microphone changes hands ("Hey Escanor" steps aside while voice mode is open).
  final void Function(bool open)? onOpenChanged;

  bool open = false;

  /// A conversation is running: keep listening after each answer.
  bool live = false;

  Future<void> talk() async {
    live = true;
    notifyListeners();
    var quiet = 0;
    while (live) {
      final outcome = await session.start();
      if (!live) break;
      if (outcome == TurnOutcome.stop) return close(); // "stop" or "that's all": leave voice mode
      if (outcome == TurnOutcome.error || outcome == TurnOutcome.cancelled) break;
      quiet = outcome == TurnOutcome.silent ? quiet + 1 : 0;
      if (quiet >= 2) break; // nobody is talking: stop listening instead of listening forever
      await Future<void>.delayed(pause);
    }
    live = false;
    notifyListeners();
  }

  void show() {
    if (!open) {
      open = true;
      onOpenChanged?.call(true);
    }
    notifyListeners();
    if (!live) talk();
  }

  void close() {
    live = false;
    session.cancel();
    if (open) {
      open = false;
      onOpenChanged?.call(false);
    }
    notifyListeners();
  }

  /// The big button: stop what is happening, or start talking again.
  void toggle() {
    if (session.phase != VoicePhase.idle || live) {
      live = false;
      session.cancel();
      notifyListeners();
    } else {
      talk();
    }
  }
}
