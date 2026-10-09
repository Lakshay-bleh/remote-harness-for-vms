/// Listening for one sentence. Pure: the recogniser is the [SpeechPlugin] interface (the real one wraps speech_to_text, see
/// speech_native.dart), so the listening logic is tested with a fake recogniser.
library;

import 'dart:async';

import 'cancel.dart';

class SpeechSubscription {
  SpeechSubscription(this.remove);
  final Future<void> Function() remove;
}

/// The slice of a speech recogniser we use. Events: `partialResults` {matches: [text]}, `listeningState` {state: 'started'|'stopped'},
/// `error` {message}.
abstract class SpeechPlugin {
  Future<void> start(Map<String, Object?> options);
  Future<void> stop();
  Future<SpeechSubscription> addListener(String event, void Function(Map<String, Object?> e) fn);
}

class SpeechError implements Exception {
  SpeechError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _str(Object? v) => v == null ? '' : '$v';

/// Listen for one spoken sentence. Resolves with what was said when the person stops talking (or the time limit passes), with ''
/// if cancelled, and fails with the recogniser's own message if it fails. Always removes its listeners, so listening twice never
/// answers twice.
Future<String> listenOnce(
  SpeechPlugin plugin, {
  void Function(String text)? onPartial,
  VoiceCancel? cancel,
  Duration timeout = const Duration(seconds: 15),
  String language = 'en-US',
}) {
  final done = Completer<String>();
  var latest = '';
  var started = false; // a "stopped" from the previous session can arrive before this one has begun: ignore it
  var finished = false;
  final handles = <SpeechSubscription>[];
  Timer? timer;
  void Function()? offAbort;

  void finish(void Function() fn) {
    if (finished) return;
    finished = true;
    timer?.cancel();
    offAbort?.call();
    Future.wait(handles.map((h) => h.remove().catchError((_) {}))).then((_) => fn(), onError: (_) => fn());
  }

  void stopPlugin() => plugin.stop().catchError((_) {});
  void onAbort() {
    stopPlugin();
    finish(() => done.complete(''));
  }

  () async {
    try {
      handles.add(await plugin.addListener('partialResults', (e) {
        final matches = e['matches'];
        final first = matches is List && matches.isNotEmpty ? matches.first : null;
        final text = _str(first ?? e['accumulatedText'] ?? e['accumulated']);
        if (text.isNotEmpty && text != latest) {
          latest = text;
          onPartial?.call(text);
        }
      }));
      handles.add(await plugin.addListener('listeningState', (e) {
        if (started && (e['state'] == 'stopped' || e['status'] == 'stopped')) finish(() => done.complete(latest));
      }));
      handles.add(await plugin.addListener('error', (e) {
        final m = _str(e['message']).isNotEmpty ? _str(e['message']) : (_str(e['code']).isNotEmpty ? _str(e['code']) : 'Speech recognition failed.');
        finish(() => done.completeError(SpeechError(m)));
      }));
      if (cancel?.aborted ?? false) return onAbort();
      offAbort = cancel?.onAbort(onAbort);
      timer = Timer(timeout, () {
        stopPlugin();
        finish(() => done.complete(latest));
      });
      await plugin.start({
        'language': language,
        'maxResults': 1,
        'partialResults': true,
        'popup': false,
        'muteRecognizerBeep': true,
        'allowForSilence': 1500,
      });
      started = true;
    } catch (e) {
      finish(() => done.completeError(e is Exception ? e : SpeechError('$e')));
    }
  }();
  return done.future;
}

enum MicState { granted, denied, unsupported }

/// Join what was already typed with what has been heard, with one space between.
String joinSpoken(String base, String heard) => [base.trimRight(), heard.trim()].where((s) => s.isNotEmpty).join(' ');
