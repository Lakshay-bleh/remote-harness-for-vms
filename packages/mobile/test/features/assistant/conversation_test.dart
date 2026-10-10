import 'dart:async';

import 'package:escanor/core/api.dart';
import 'package:escanor/features/assistant/chat_state.dart';
import 'package:escanor/features/assistant/conversation.dart';
import 'package:escanor/features/composer/attachments.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements ConversationBackend {
  final sent = <({String text, String? id, List<ApiAttachment> attachments})>[];
  final answers = <({String id, String requestId, bool allow})>[];
  final asked = <({String id, int after})>[];
  AssistantMessages next = const AssistantMessages();
  Object? sendError;
  Object? answerError;
  String newId = 'c1';
  int stops = 0;
  final stopped = <String>[];
  Object? stopError;
  Completer<String>? sendGate;

  @override
  Future<AssistantMessages> messages(String id, int after) async {
    asked.add((id: id, after: after));
    return next;
  }

  @override
  Future<String> send(String text, String? conversationId, List<ApiAttachment> attachments, {String? model}) async {
    sent.add((text: text, id: conversationId, attachments: attachments));
    if (sendError != null) throw sendError!;
    if (sendGate != null) return sendGate!.future;
    return conversationId ?? newId;
  }

  @override
  Future<void> answer(String id, String requestId, bool allow) async {
    answers.add((id: id, requestId: requestId, allow: allow));
    if (answerError != null) throw answerError!;
  }

  @override
  Future<bool> stop(String id) async {
    stops++;
    stopped.add(id);
    if (stopError != null) throw stopError!;
    return true;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a first message shows at once, creates the conversation and reports it once', () async {
    final b = FakeBackend();
    final created = <String>[];
    final chat = Conversation(onCreated: created.add, backend: b);
    final f = chat.send('  hello  ');
    expect(toDisplay(chat.state).single.text, 'hello');
    expect(toDisplay(chat.state).single.optimistic, true);
    await f;
    expect(b.sent.single.text, 'hello');
    expect(b.sent.single.id, null);
    expect(chat.id, 'c1');
    expect(created, ['c1']);
    // the screen then opens the same conversation: nothing is thrown away
    chat.open('c1');
    expect(toDisplay(chat.state).length, 1);
    await chat.send('again');
    expect(b.sent.last.id, 'c1');
    expect(created, ['c1']);
    chat.dispose();
  });

  test('nothing to send is not sent', () async {
    final b = FakeBackend();
    final chat = Conversation(onCreated: (_) {}, backend: b);
    await chat.send('   ');
    expect(b.sent, isEmpty);
    expect(chat.state.items, isEmpty);
    chat.dispose();
  });

  test('attachments travel with the message and are noted in the chat', () async {
    final b = FakeBackend();
    final chat = Conversation(onCreated: (_) {}, backend: b);
    await chat.send('look', [Attachment(name: 'err.log', mime: 'text/plain', kind: AttachmentKind.text, size: 4, text: 'boom')]);
    expect(chat.state.items.single.text, 'look\n\n[Attached: err.log]');
    expect(b.sent.single.attachments.single.toJson(), {'name': 'err.log', 'mime': 'text/plain', 'kind': 'text', 'text': 'boom'});
    chat.dispose();
  });

  test('a failed send takes the message back and says why', () async {
    final b = FakeBackend()..sendError = ApiError('Daily limit reached.', 429);
    final chat = Conversation(onCreated: (_) {}, backend: b);
    await chat.send('hi');
    expect(chat.state.items, isEmpty);
    expect(chat.state.running, false);
    expect(chat.error, 'Daily limit reached.');
    chat.dispose();
  });

  test('opening a conversation loads its history from the start, and switching starts again', () async {
    final b = FakeBackend()
      ..next = const AssistantMessages(items: [AssistantItem(id: 1, kind: 'user', text: 'q'), AssistantItem(id: 2, kind: 'assistant', text: 'a')], lastId: 2);
    final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
    await settle();
    expect(b.asked.first, (id: 'x', after: 0));
    expect(toDisplay(chat.state).map((d) => d.type), [BlockType.user, BlockType.assistant]);
    b.next = const AssistantMessages();
    chat.open('y');
    expect(chat.state.items, isEmpty);
    await settle();
    expect(b.asked.last, (id: 'y', after: 0));
    chat.open(null);
    expect(chat.id, null);
    chat.dispose();
  });

  test('an answer shows at once and goes to the server; a failure is reported', () async {
    final b = FakeBackend()
      ..next = const AssistantMessages(items: [AssistantItem(id: 1, kind: 'approval', requestId: 'r1', title: 'Run')], running: true, pending: 1, lastId: 1);
    final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
    await settle();
    final f = chat.answer('r1', true);
    expect(chat.state.items.single.status, 'allowed');
    await f;
    expect(b.answers.single, (id: 'x', requestId: 'r1', allow: true));
    b.answerError = ApiError('Too late.', 409);
    await chat.answer('r1', false);
    expect(chat.error, 'Too late.');
    await chat.stop();
    expect(b.stops, 1);
    chat.dispose();
  });

  test('polls that keep failing are reported once there are enough of them, and keep trying until one works', () {
    fakeAsync((async) {
      final b = _FailingBackend()
        ..next = const AssistantMessages(items: [AssistantItem(id: 1, kind: 'user', text: 'q')], lastId: 1);
      final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
      async.flushMicrotasks();
      expect(chat.error, null, reason: 'one failure is a blip, not news');
      // backing off, but never giving up
      for (var i = 0; i < pollFailuresToReport - 1; i++) {
        async.elapse(const Duration(seconds: 9));
      }
      expect(b.calls, pollFailuresToReport);
      expect(chat.error, 'Can’t reach your assistant. Retrying…');
      expect(chat.canSend, true);
      b.failing = false;
      async.elapse(const Duration(seconds: 9));
      expect(chat.error, null);
      expect(chat.state.items.single.text, 'q');
      chat.dispose();
    });
  });

  test('polls do not overlap, and a failed one does not clear what the person did wrong', () {
    fakeAsync((async) {
      final b = FakeBackend()..sendError = ApiError('Daily limit reached.', 429);
      final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
      async.flushMicrotasks();
      chat.send('hi');
      async.flushMicrotasks();
      expect(chat.error, 'Daily limit reached.');
      async.elapse(const Duration(seconds: 20));
      expect(chat.error, 'Daily limit reached.', reason: 'polls never clear it');
      chat.dispose();
    });
  });

  group('stopping a turn', () {
    const running = AssistantMessages(items: [AssistantItem(id: 1, kind: 'user', text: 'deploy')], running: true, lastId: 1);
    const ended = AssistantMessages(
      items: [AssistantItem(id: 1, kind: 'user', text: 'deploy'), AssistantItem(id: 2, kind: 'notice', text: 'Stopped.')],
      lastId: 2,
    );

    test('stop goes to the server once, shows it is stopping, and clears when the turn ends', () {
      fakeAsync((async) {
        var now = 0;
        final b = FakeBackend()..next = running;
        final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b, now: () => now);
        async.flushMicrotasks();
        expect(chat.state.running, true);
        expect(chat.canSend, false);
        chat.stop();
        expect(chat.stopping, true);
        async.flushMicrotasks();
        expect(b.stopped, ['x']);
        chat.stop(); // pressing again while it is on its way does nothing
        async.flushMicrotasks();
        expect(b.stopped, ['x']);
        expect(chat.stopPhase.kind, StopKind.sent);
        b.next = ended;
        async.elapse(const Duration(seconds: 1));
        expect(chat.state.running, false);
        expect(chat.stopping, false);
        expect(chat.stopPhase, StopPhase.idle);
        expect(toDisplay(chat.state).last.type, BlockType.notice);
        chat.dispose();
      });
    });

    test('a stop the server does not act on is reported after the grace time, and can be sent again', () {
      fakeAsync((async) {
        var now = 0;
        final b = FakeBackend()..next = running;
        final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b, now: () => now);
        async.flushMicrotasks();
        chat.stop();
        async.flushMicrotasks();
        now = stopGraceMs + 1;
        async.elapse(const Duration(seconds: 1));
        expect(chat.error, 'It is taking a long time to stop. You can send a new message, or try Stop again.');
        expect(chat.stopping, false);
        expect(chat.canSend, true, reason: 'a turn that looks lost does not lock the person out');
        chat.stop();
        async.flushMicrotasks();
        expect(b.stopped, ['x', 'x']);
        expect(chat.error, null);
        chat.dispose();
      });
    });

    test('stop pressed before the new chat has an id is sent the moment it does', () {
      fakeAsync((async) {
        final b = FakeBackend()..sendGate = Completer<String>();
        final created = <String>[];
        final chat = Conversation(onCreated: created.add, backend: b);
        chat.send('deploy');
        async.flushMicrotasks();
        expect(chat.state.running, true);
        chat.stop();
        expect(chat.stopPhase, StopPhase.queued);
        expect(chat.stopping, true);
        expect(b.stopped, isEmpty);
        b.sendGate!.complete('c9');
        async.flushMicrotasks();
        expect(created, ['c9']);
        expect(b.stopped, ['c9']);
        chat.dispose();
      });
    });

    test('a stop that fails says so and can be tried again', () {
      fakeAsync((async) {
        final b = FakeBackend()
          ..next = running
          ..stopError = ApiError('Server error.', 500);
        final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
        async.flushMicrotasks();
        chat.stop();
        async.flushMicrotasks();
        expect(chat.error, 'Could not stop it. Server error.');
        expect(chat.stopPhase, StopPhase.idle);
        b.stopError = null;
        chat.stop();
        async.flushMicrotasks();
        expect(b.stopped, ['x', 'x']);
        expect(chat.error, null);
        chat.dispose();
      });
    });

    test('switching chats forgets a stop meant for the other one', () {
      fakeAsync((async) {
        final b = FakeBackend()..next = running;
        final chat = Conversation(id: 'x', onCreated: (_) {}, backend: b);
        async.flushMicrotasks();
        chat.stop();
        chat.open('y');
        async.flushMicrotasks();
        expect(chat.stopPhase, StopPhase.idle);
        chat.dispose();
      });
    });
  });
}

class _FailingBackend extends FakeBackend {
  bool failing = true;
  int calls = 0;
  @override
  Future<AssistantMessages> messages(String id, int after) {
    calls++;
    if (failing) return Future.error(ApiError('Could not reach Escanor. Check your connection.', 0));
    return super.messages(id, after);
  }
}
