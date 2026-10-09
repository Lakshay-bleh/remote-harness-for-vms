import 'package:escanor/features/voice/cancel.dart';
import 'package:escanor/features/voice/speech.dart';
import 'package:flutter_test/flutter_test.dart';

/// A speech recogniser we can drive: emit partials, then stop.
class FakeRecogniser implements SpeechPlugin {
  final Map<String, List<void Function(Map<String, Object?>)>> handlers = {};
  final List<Map<String, Object?>> started = [];
  int stops = 0;

  @override
  Future<void> start(Map<String, Object?> options) async => started.add(options);
  @override
  Future<void> stop() async => stops += 1;
  @override
  Future<SpeechSubscription> addListener(String event, void Function(Map<String, Object?> e) fn) async {
    (handlers[event] ??= []).add(fn);
    return SpeechSubscription(() async => handlers[event]!.remove(fn));
  }

  void emit(String name, [Map<String, Object?> e = const {}]) {
    for (final h in List.of(handlers[name] ?? const <void Function(Map<String, Object?>)>[])) {
      h(e);
    }
  }

  int get listeners => handlers.values.fold(0, (n, l) => n + l.length);
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('listenOnce', () {
    test('shows what is heard as it comes, and resolves with the last thing heard when listening stops', () async {
      final r = FakeRecogniser();
      final shown = <String>[];
      final p = listenOnce(r, onPartial: shown.add);
      await tick();
      r.emit('partialResults', {
        'matches': ['open'],
      });
      r.emit('partialResults', {
        'matches': ['open youtube'],
      });
      r.emit('listeningState', {'state': 'stopped'});
      expect(await p, 'open youtube');
      expect(shown, ['open', 'open youtube']);
    });

    test('asks for partial results, no system dialog, and no beep', () async {
      final r = FakeRecogniser();
      final p = listenOnce(r);
      await tick();
      r.emit('listeningState', {'status': 'stopped'});
      await p;
      expect(r.started.first, {'language': 'en-US', 'maxResults': 1, 'partialResults': true, 'popup': false, 'muteRecognizerBeep': true, 'allowForSilence': 1500});
    });

    test('cleans up its listeners every time, so a second listen is not answered twice', () async {
      final r = FakeRecogniser();
      final p = listenOnce(r);
      await tick();
      r.emit('listeningState', {'state': 'stopped'});
      await p;
      expect(r.listeners, 0);
    });

    test('fails with the recogniser’s own message when it errors', () async {
      final r = FakeRecogniser();
      final p = listenOnce(r);
      await tick();
      r.emit('error', {'message': 'No speech detected'});
      await expectLater(p, throwsA(isA<SpeechError>().having((e) => e.message, 'message', 'No speech detected')));
      expect(r.listeners, 0);
    });

    test('gives up after the time limit with what it has, and stops the recogniser', () async {
      final r = FakeRecogniser();
      final p = listenOnce(r, timeout: const Duration(milliseconds: 40));
      await tick();
      r.emit('partialResults', {
        'matches': ['hello there'],
      });
      expect(await p, 'hello there');
      expect(r.stops, 1);
    });

    test('can be cancelled, and then resolves with nothing', () async {
      final r = FakeRecogniser();
      final c = VoiceCancel();
      final p = listenOnce(r, cancel: c);
      await tick();
      r.emit('partialResults', {
        'matches': ['never mind'],
      });
      c.abort();
      expect(await p, '');
      expect(r.stops, 1);
    });

    test('ignores a "stopped" that arrives before anything was started listening (the stop of an earlier session)', () async {
      final r = FakeRecogniser();
      final p = listenOnce(r, timeout: const Duration(milliseconds: 60));
      r.emit('listeningState', {'state': 'stopped'}); // before start() has even resolved
      await tick();
      r.emit('partialResults', {
        'matches': ['real words'],
      });
      r.emit('listeningState', {'state': 'stopped'});
      expect(await p, 'real words');
    });
  });

  group('joinSpoken', () {
    test('adds what was heard after what was typed, with one space', () {
      expect(joinSpoken('open the', 'pod bay doors'), 'open the pod bay doors');
      expect(joinSpoken('trailing   ', 'words'), 'trailing words');
    });
    test('is just the speech when nothing was typed, and just the text when nothing was heard', () {
      expect(joinSpoken('', 'hello'), 'hello');
      expect(joinSpoken('typed', ''), 'typed');
      expect(joinSpoken('', ''), '');
    });
  });
}
