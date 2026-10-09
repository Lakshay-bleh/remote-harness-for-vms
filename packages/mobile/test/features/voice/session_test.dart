import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/features/assistant/chat_state.dart';
import 'package:escanor/features/voice/ask_assistant.dart';
import 'package:escanor/features/voice/assistant.dart';
import 'package:escanor/features/voice/assistant_answer.dart';
import 'package:escanor/features/voice/cancel.dart';
import 'package:escanor/features/voice/speech.dart';
import 'package:escanor/features/voice/voice_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A phone for one conversation: what the person will say, turn by turn ('' = silence), and what was spoken back.
class Script {
  Script(this.heard, {this.mic = MicState.granted});
  final List<String> heard;
  final MicState mic;
  final List<String> spoken = [];
  int listens = 0;

  VoiceIo get io => VoiceIo(
        ensureMic: () async => mic,
        listen: ({onPartial, cancel}) async {
          final said = listens < heard.length ? heard[listens] : '';
          listens++;
          if (said.isNotEmpty) onPartial?.call(said);
          return said;
        },
        speak: (t) async => spoken.add(t),
        stopSpeaking: () async {},
        ios: () => false,
      );
}

VoiceHandler echo() => (said, {required interim, required cancel}) async =>
    said == 'stop' ? const Reply(ok: true, say: 'Okay.', kind: ReplyKind.stop) : Reply(ok: true, say: 'You said $said.', kind: ReplyKind.assistant);

void main() {
  group('one turn', () {
    test('listens, does it, and says what happened', () async {
      final s = Script(['open youtube']);
      final v = VoiceSession(handle: echo(), io: s.io);
      expect(await v.start(), TurnOutcome.spoke);
      expect(v.heard, 'open youtube');
      expect(v.reply?.say, 'You said open youtube.');
      expect(v.phase, VoicePhase.idle);
      expect(s.spoken, ['You said open youtube.']);
    });

    test('says how to allow the microphone when it is refused', () async {
      final v = VoiceSession(handle: echo(), io: Script([], mic: MicState.denied).io);
      expect(await v.start(), TurnOutcome.error);
      expect(v.reply?.say, contains('In Android Settings, open Apps, then Escanor, then Permissions, and allow the microphone.'));
    });

    test('silence is not an error', () async {
      final v = VoiceSession(handle: echo(), io: Script(['']).io);
      expect(await v.start(), TurnOutcome.silent);
      expect(v.reply, isNull);
    });

    test('says why it could not hear', () async {
      final io = VoiceIo(
        ensureMic: () async => MicState.granted,
        listen: ({onPartial, cancel}) async => throw SpeechError('The microphone could not be used.'),
        speak: (_) async {},
        stopSpeaking: () async {},
        ios: () => false,
      );
      final v = VoiceSession(handle: echo(), io: io);
      expect(await v.start(), TurnOutcome.error);
      expect(v.reply?.say, 'I couldn’t hear you. The microphone could not be used. Check the microphone permission in Android Settings, under Apps, Escanor.');
    });
  });

  group('voice mode', () {
    test('keeps listening after each answer, and leaves on "stop"', () async {
      final s = Script(['one', 'two', 'stop']);
      final c = VoiceConversation(VoiceSession(handle: echo(), io: s.io), pause: Duration.zero);
      c.open = true;
      await c.talk();
      expect(s.spoken, ['You said one.', 'You said two.', 'Okay.']);
      expect(c.open, false);
    });

    test('stops listening after two silences in a row, instead of listening forever', () async {
      final s = Script(['one', '', '', 'never heard']);
      final c = VoiceConversation(VoiceSession(handle: echo(), io: s.io), pause: Duration.zero);
      await c.talk();
      expect(s.listens, 3);
      expect(c.live, false);
    });

    test('tells the microphone owner when it opens and closes', () async {
      final changes = <bool>[];
      final c = VoiceConversation(VoiceSession(handle: echo(), io: Script(['stop']).io), pause: Duration.zero, onOpenChanged: changes.add);
      c.show();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(changes, [true, false]);
    });
  });

  group('askAssistant', () {
    setUp(() async {
      await Storage.initForTest(secrets: {'escanor_access': 'a', 'escanor_refresh': 'r'});
    });

    test('sends into the open conversation, points the app at it, and returns the answer', () async {
      final sent = <Map<String, Object?>>[];
      api = Api(
        base: 'https://x.test/api/v1',
        client: MockClient((req) async {
          if (req.url.path.endsWith('/ai/chat')) {
            sent.add(jsonDecode(req.body) as Map<String, Object?>);
            return http.Response(jsonEncode({'conversation_id': 'c1'}), 200);
          }
          return http.Response(
              jsonEncode({
                'items': [
                  {'id': 1, 'kind': 'user', 'text': 'status'},
                  {'id': 2, 'kind': 'assistant', 'text': 'All good.'},
                ],
                'approvals': [],
                'running': false,
                'pending': 0,
                'last_id': 2,
              }),
              200);
        }),
      );
      String? opened;
      final r = await askAssistant('status', VoiceCancel(), conversationId: 'c0', setConversation: (id) => opened = id);
      expect(r, 'All good.');
      expect(sent.single, {'text': 'status', 'conversation_id': 'c0'});
      expect(opened, 'c1');
    });

    test('says the answer will be in the chat when it takes too long', () async {
      api = Api(base: 'https://x.test/api/v1', client: MockClient((req) async => http.Response(jsonEncode({'conversation_id': 'c2'}), 200)));
      var t = DateTime(2026);
      final r = await askAssistant(
        'deploy',
        VoiceCancel(),
        conversationId: null,
        setConversation: (_) {},
        deps: AnswerDeps(
          fetch: (_) async => AssistantMessages.fromJson({'items': [], 'approvals': [], 'running': true, 'pending': 0, 'last_id': 0}),
          wait: (d) async => t = t.add(d),
          now: () => t,
        ),
      );
      expect(r, 'Still working on it. The answer will be in the chat.');
    });

    test('speaking while the open chat is still answering stops that and asks again', () async {
      final b = _AskFake()..busyOnce = true;
      String? opened;
      final r = await askAssistant('status', VoiceCancel(), conversationId: 'c0', setConversation: (id) => opened = id, backend: b, deps: b.deps());
      expect(b.calls, ['send c0', 'stop c0', 'messages c0', 'send c0', 'messages c0']);
      expect(opened, 'c0');
      expect(r, 'All good.');
    });

    test('a chat that will not stop is left alone, and the person is told', () async {
      final b = _AskFake()
        ..busyOnce = true
        ..stuck = true;
      final r = await askAssistant('status', VoiceCancel(), conversationId: 'c0', setConversation: (_) {}, backend: b, deps: b.deps());
      expect(r, 'I’m still finishing your last request in this chat. Open it to follow along, or stop it there.');
      expect(b.calls.where((c) => c.startsWith('send')).length, 1);
    });

    test('a 409 for a new chat is a real error', () async {
      final b = _AskFake()..busyOnce = true;
      await expectLater(askAssistant('status', VoiceCancel(), conversationId: null, setConversation: (_) {}, backend: b, deps: b.deps()), throwsA(isA<ApiError>()));
    });

    test('cancelling voice mode stops the turn it started, not only the waiting', () async {
      final b = _AskFake()..running = true;
      final cancel = VoiceCancel();
      final f = askAssistant('deploy', cancel, conversationId: null, setConversation: (_) {}, backend: b, deps: b.deps(onWait: () => cancel.abort()));
      await f;
      expect(b.calls, contains('stop new1'));
    });
  });
}

class _AskFake extends AskBackend {
  final calls = <String>[];
  bool busyOnce = false;
  bool stuck = false;
  bool running = false;

  @override
  Future<String> send(String text, String? conversationId) async {
    calls.add('send $conversationId');
    if (busyOnce) {
      busyOnce = false;
      throw ApiError('The assistant is still answering.', 409);
    }
    return conversationId ?? 'new1';
  }

  @override
  Future<AssistantMessages> messages(String id, int after) async {
    calls.add('messages $id');
    final busy = running || (stuck && calls.where((c) => c.startsWith('send')).length == 1);
    return AssistantMessages.fromJson({
      'items': busy
          ? [
              {'id': 1, 'kind': 'user', 'text': 'status'},
            ]
          : [
              {'id': 1, 'kind': 'user', 'text': 'status'},
              {'id': 2, 'kind': 'assistant', 'text': 'All good.'},
            ],
      'approvals': [],
      'running': busy,
      'pending': 0,
      'last_id': busy ? 1 : 2,
    });
  }

  @override
  Future<bool> stop(String id) async {
    calls.add('stop $id');
    return true;
  }

  AnswerDeps deps({void Function()? onWait}) {
    var t = DateTime(2026);
    return AnswerDeps(
      fetch: (after) => messages(calls.lastWhere((c) => c.startsWith('send')).split(' ').last == 'null' ? 'new1' : 'c0', after),
      wait: (d) async {
        onWait?.call();
        t = t.add(d);
      },
      now: () => t,
    );
  }
}
