import 'package:escanor/features/assistant/chat_state.dart';
import 'package:escanor/features/voice/assistant_answer.dart';
import 'package:escanor/features/voice/cancel.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> msg(int id, String kind, [Map<String, Object?> extra = const {}]) => {'id': id, 'kind': kind, ...extra};

AssistantMessages page(List<Map<String, Object?>> items, [bool running = false]) => AssistantMessages.fromJson({
      'items': items,
      'approvals': const [],
      'running': running,
      'pending': 0,
      'last_id': items.fold<int>(0, (m, i) => (i['id'] as int) > m ? i['id'] as int : m),
    });

({DateTime Function() now, Future<void> Function(Duration) wait}) clock() {
  var t = DateTime(2026);
  return (now: () => t, wait: (d) async => t = t.add(d));
}

void main() {
  group('waitForAnswer', () {
    test('returns what the assistant said to the sentence just sent, not an earlier answer', () async {
      final c = clock();
      final pages = [
        page([msg(1, 'user', {'text': 'hi'}), msg(2, 'assistant', {'text': 'Hello!'})]),
        page([msg(1, 'user', {'text': 'hi'}), msg(2, 'assistant', {'text': 'Hello!'}), msg(3, 'user', {'text': 'status'})], true),
        page([
          msg(1, 'user', {'text': 'hi'}),
          msg(2, 'assistant', {'text': 'Hello!'}),
          msg(3, 'user', {'text': 'status'}),
          msg(4, 'assistant', {'text': 'All good.'}),
        ]),
      ];
      var n = 0;
      final r = await waitForAnswer(AnswerDeps(fetch: (_) async => pages[n++ < pages.length - 1 ? n - 1 : pages.length - 1], wait: c.wait, now: c.now), 'status');
      expect(r.text, 'All good.');
      expect(r.timedOut, false);
    });

    test('says it needs an OK when the assistant stopped to ask', () async {
      final c = clock();
      final r = await waitForAnswer(
        AnswerDeps(
          fetch: (_) async => page([
            msg(1, 'user', {'text': 'deploy'}),
            msg(2, 'approval', {'request_id': 'r1', 'status': 'pending', 'title': 'Run deploy'}),
          ], true),
          wait: c.wait,
          now: c.now,
        ),
        'deploy',
      );
      expect(r, const Answer(text: '', needsApproval: true, timedOut: false));
    });

    test('gives up after the time limit with nothing, and says it timed out', () async {
      final c = clock();
      final r = await waitForAnswer(AnswerDeps(fetch: (_) async => page([]), wait: c.wait, now: c.now), 'x', timeout: const Duration(seconds: 5));
      expect(r, const Answer(text: '', needsApproval: false, timedOut: true));
    });

    test('stops quietly when cancelled', () async {
      final c = clock();
      final cancel = VoiceCancel()..abort();
      final r = await waitForAnswer(AnswerDeps(fetch: (_) async => throw Exception('unreachable'), wait: c.wait, now: c.now), 'x', cancel: cancel);
      expect(r.timedOut, false);
    });
  });

  group('forSpeech', () {
    test('drops markdown and code, which are for the eye', () {
      expect(forSpeech('## Result\n\n- **3** services are `up`\n- see [the docs](https://x.y)\n\n```\nrm -rf /\n```'), 'Result 3 services are up see the docs (some code)');
    });
    test('shortens a long answer at a sentence and points to the chat', () {
      final long = 'First point is here. ' * 40;
      final out = forSpeech(long, 100);
      expect(out.length, lessThan(160));
      expect(out, endsWith('The rest is in the chat.'));
      expect(out, matches(RegExp(r'point is here\. The rest')));
    });
    test('leaves a short answer alone', () => expect(forSpeech('All good.'), 'All good.'));
  });

  group('waitForAnswer, a stopped turn', () {
    test('answers with the stop notice instead of waiting out the time limit', () async {
      final c = clock();
      final pages = [
        page([msg(1, 'user', {'text': 'deploy'})], true),
        page([msg(1, 'user', {'text': 'deploy'}), msg(2, 'notice', {'text': 'Stopped.'})], false),
      ];
      var n = 0;
      final r = await waitForAnswer(AnswerDeps(fetch: (_) async => pages[n++ < pages.length - 1 ? n - 1 : pages.length - 1], wait: c.wait, now: c.now), 'deploy');
      expect(r, const Answer(text: 'Stopped.', needsApproval: false, timedOut: false));
    });

    test('keeps waiting through a notice in the middle of a turn, and returns the words that follow', () async {
      final c = clock();
      final pages = [
        page([msg(1, 'user', {'text': 'hi'}), msg(2, 'notice', {'text': 'A was not available, so B is answering.'})], true),
        page([
          msg(1, 'user', {'text': 'hi'}),
          msg(2, 'notice', {'text': 'A was not available, so B is answering.'}),
          msg(3, 'assistant', {'text': 'Hello.'}),
        ], false),
      ];
      var n = 0;
      final r = await waitForAnswer(AnswerDeps(fetch: (_) async => pages[n++ < pages.length - 1 ? n - 1 : pages.length - 1], wait: c.wait, now: c.now), 'hi');
      expect(r.text, 'Hello.');
    });
  });
}
