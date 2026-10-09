import 'package:escanor/features/assistant/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

AssistantMessages res({
  List<AssistantItem> items = const [],
  List<({String requestId, String status})> approvals = const [],
  bool running = false,
  int pending = 0,
  int lastId = 0,
  AssistantProgress? progress,
}) =>
    AssistantMessages(items: items, approvals: approvals, running: running, pending: pending, lastId: lastId, progress: progress);
AssistantItem user(int id, String text) => AssistantItem(id: id, kind: 'user', text: text);
AssistantItem assistant(int id, String text) => AssistantItem(id: id, kind: 'assistant', text: text);
AssistantItem activity(int id, String text) => AssistantItem(id: id, kind: 'activity', text: text);
AssistantItem approval(int id, String requestId, [String status = 'pending']) =>
    AssistantItem(id: id, kind: 'approval', requestId: requestId, status: status, title: 'Run a command', detail: 'ls', raw: 'ls');

List<BlockType> types(ChatState s) => toDisplay(s).map((b) => b.type).toList();

void main() {
  test('a message shows at once, then is replaced (not duplicated) by the real one', () {
    var s = addOptimisticMessage(emptyChat, 'hello');
    expect(toDisplay(s).length, 1);
    expect(s.running, true);
    s = applyMessages(s, res(items: [user(1, 'hello')], running: true, lastId: 1));
    expect(types(s), [BlockType.user]);
    expect(toDisplay(s)[0].optimistic, false);
  });

  test('two identical messages sent in a row stay two', () {
    var s = addOptimisticMessage(addOptimisticMessage(emptyChat, 'again'), 'again');
    s = applyMessages(s, res(items: [user(1, 'again')], running: true, lastId: 1));
    expect(toDisplay(s).where((b) => b.type == BlockType.user).length, 2, reason: 'one confirmed, one still pending');
    s = applyMessages(s, res(items: [user(2, 'again')], running: true, lastId: 2));
    expect(toDisplay(s).where((b) => b.type == BlockType.user).length, 2);
    expect(toDisplay(s).every((b) => !b.optimistic), true);
  });

  test('a failed send takes the optimistic message back', () {
    final s = dropOptimisticMessages(addOptimisticMessage(emptyChat, 'oops'));
    expect(s.items, isEmpty);
    expect(s.running, false);
  });

  test('applying the same response twice changes nothing', () {
    final r = res(items: [user(1, 'a'), assistant(2, 'b')], lastId: 2);
    final once = applyMessages(emptyChat, r);
    final twice = applyMessages(once, r);
    expect(twice.items.map((i) => i.id), once.items.map((i) => i.id));
    expect(twice.lastId, 2);
  });

  test('polls append only what is new', () {
    var s = applyMessages(emptyChat, res(items: [user(1, 'a')], lastId: 1, running: true));
    s = applyMessages(s, res(items: [assistant(2, 'b')], lastId: 2, running: false));
    expect(s.items.map((i) => i.kind), ['user', 'assistant']);
    expect(s.running, false);
    expect(s.lastId, 2, reason: 'the cursor covers rows the person never sees too');
    s = applyMessages(s, res(items: [], lastId: 9));
    expect(s.lastId, 9);
  });

  test('an answer updates the question the page already has', () {
    var s = applyMessages(emptyChat, res(items: [user(1, 'x'), approval(2, 'r1')], lastId: 2, running: true, pending: 1));
    expect(toDisplay(s)[1].item!.status, 'pending');
    s = applyMessages(s, res(approvals: [(requestId: 'r1', status: 'allowed')], lastId: 2, running: true, pending: 0));
    expect(toDisplay(s)[1].item!.status, 'allowed');
  });

  test('clicking Continue reflects immediately, and only once', () {
    var s = applyMessages(emptyChat, res(items: [approval(2, 'r1')], lastId: 2, running: true, pending: 1));
    s = markAnswered(s, 'r1', true);
    expect(s.pending, 0);
    expect(toDisplay(s)[0].item!.status, 'allowed');
    s = markAnswered(s, 'r1', false);
    expect(toDisplay(s)[0].item!.status, 'allowed', reason: 'an answered question is not re-answered');
    expect(s.pending, 0, reason: 'and pending never goes negative');
  });

  test('repeated activity collapses to one quiet line, and only the latest pulses', () {
    final items = [
      user(1, 'q'),
      activity(2, 'Checking which services are available'),
      activity(3, 'Checking which services are available'),
      activity(4, 'Using Escanor — GitHub: list repos'),
    ];
    final running = toDisplay(applyMessages(emptyChat, res(items: items, lastId: 4, running: true)));
    expect(running.map((b) => b.type), [BlockType.user, BlockType.activity, BlockType.activity]);
    expect(running.where((b) => b.type == BlockType.activity).map((b) => b.live), [false, true]);
    final finished = toDisplay(applyMessages(emptyChat, res(items: items, lastId: 4, running: false)));
    expect(finished.every((b) => b.type != BlockType.activity || !b.live), true, reason: 'nothing pulses once it is done');
  });

  test('the turn-finished marker and expired questions are not drawn', () {
    final s = applyMessages(
        emptyChat, res(items: [user(1, 'x'), approval(2, 'r1', 'expired'), const AssistantItem(id: 3, kind: 'done'), assistant(4, 'ok')], lastId: 4));
    expect(types(s), [BlockType.user, BlockType.assistant]);
  });

  test('the thinking indicator is for waiting on the assistant, never on the person', () {
    expect(isThinking(addOptimisticMessage(emptyChat, 'hi')), true);
    final asking = applyMessages(emptyChat, res(items: [user(1, 'x'), approval(2, 'r1')], lastId: 2, running: true, pending: 1));
    expect(isThinking(asking), false, reason: 'waiting for the person to answer is not "thinking"');
    final talking = applyMessages(emptyChat, res(items: [user(1, 'x'), assistant(2, 'here you go')], lastId: 2, running: true));
    expect(isThinking(talking), false);
    expect(isThinking(emptyChat), false);
  });

  test('polling is quick while working and patient when idle', () {
    expect(pollDelayMs(emptyChat.copyWith(running: true)), 700);
    expect(pollDelayMs(emptyChat.copyWith(pending: 1)), 1500);
    expect(pollDelayMs(emptyChat), greaterThanOrEqualTo(5000));
  });

  test('usage is described in messages, not dollars, and warns before the limit', () {
    UsageSummary at(int messages, [int tokens = 0]) => describeUsage(messagesToday: messages, messageLimit: 200, todayTokens: tokens);
    expect(at(12, 45300), const UsageSummary(messages: '12 of 200 messages today', tokens: '45.3k tokens', ratio: 0.06, level: 'ok'));
    expect(at(160).level, 'warn');
    expect(at(200).level, 'full');
    expect(at(999).ratio, 1, reason: 'never shows more than full');
    expect(at(3).tokens, null, reason: 'no tokens, nothing to say');
    final unlimited = describeUsage(messagesToday: 1, messageLimit: null, todayTokens: 2000000);
    expect(unlimited, const UsageSummary(messages: '1 message today', tokens: '2M tokens', ratio: null, level: 'ok'));
    expect(unlimited.toString().contains(r'$'), false);
  });

  test('the server’s shapes are read defensively', () {
    final m = AssistantMessages.fromJson({
      'items': [
        {'id': 1, 'kind': 'user', 'text': 'hi'},
        {'id': 2, 'kind': 'approval', 'request_id': 'r', 'status': 'pending', 'title': 'T', 'detail': 'D', 'risk': 'high', 'raw': 'x'},
      ],
      'approvals': [
        {'request_id': 'r', 'status': 'allowed'},
      ],
      'running': true,
      'pending': 1,
      'last_id': 2,
    });
    expect(m.items.length, 2);
    expect(m.items[1].risk, 'high');
    expect(m.approvals.single.status, 'allowed');
    expect(m.lastId, 2);
    expect(AssistantMessages.fromJson(null).items, isEmpty);
    final caps = AssistantCapabilities.fromJson({
      'machine': {'state': 'running'},
      'integrations': [
        {'provider_id': 'github', 'name': 'GitHub', 'connected': true, 'available_to_assistant': true},
        {'provider_id': 'x', 'name': 'X', 'connected': true, 'available_to_assistant': null},
      ],
    });
    expect(caps.machineState, 'running');
    expect(caps.integrations.where((i) => i.availableToAssistant == true).map((i) => i.name), ['GitHub']);
    expect(MachineView.fromJson({}).state, 'unknown');
  });

  // -------------------------------------------------------------------------- notices, progress, stopping

  AssistantItem notice(int id, String text) => AssistantItem(id: id, kind: 'notice', text: text);

  test('a notice is drawn as its own quiet line, and a stopped turn ends on it', () {
    var s = applyMessages(emptyChat, res(items: [user(1, 'deploy'), activity(2, 'Checking'), notice(3, 'Stopped.')], lastId: 3));
    expect(types(s), [BlockType.user, BlockType.activity, BlockType.notice]);
    expect(toDisplay(s)[2].text, 'Stopped.');
    expect(isThinking(s), false);
    s = applyMessages(emptyChat, res(items: [user(1, 'hi'), notice(2, 'A was not available, so B is answering.')], running: true, lastId: 2));
    expect(isThinking(s), true, reason: 'a notice mid-turn is still waiting on the answer');
  });

  test('progress is kept while running, dropped when the turn ends, and absent from older servers', () {
    const progress = AssistantProgress(text: 'Asking GPT OSS 120b · step 2', since: '2026-10-07T10:00:00Z', step: 2);
    var s = applyMessages(emptyChat, res(items: [user(1, 'hi')], running: true, lastId: 1, progress: progress));
    expect(s.progress, progress);
    s = applyMessages(s, res(running: false, lastId: 1, progress: progress));
    expect(s.progress, null);
    s = applyMessages(emptyChat, res(running: true));
    expect(s.progress, null);
    expect(dropOptimisticMessages(s.copyWith(progress: () => progress)).progress, null);
    // empty text is no progress
    expect(applyMessages(emptyChat, res(running: true, progress: const AssistantProgress(text: '', since: 'x'))).progress, null);
  });

  test('progress is read from the messages response, and ignored when it is not one', () {
    final m = AssistantMessages.fromJson({
      'items': [],
      'approvals': [],
      'running': true,
      'pending': 0,
      'last_id': 0,
      'progress': {'text': 'Asking GPT OSS 120b · step 2', 'since': '2026-10-07T10:00:00Z', 'step': 2},
    });
    expect(m.progress, const AssistantProgress(text: 'Asking GPT OSS 120b · step 2', since: '2026-10-07T10:00:00Z', step: 2));
    expect(AssistantMessages.fromJson({'progress': null}).progress, null);
    expect(AssistantMessages.fromJson({'progress': 'busy'}).progress, null);
    expect(AssistantMessages.fromJson({'progress': {'since': 'x'}}).progress, null);
    expect(AssistantMessages.fromJson({}).progress, null);
  });

  test('the thinking line says what it is doing and for how long', () {
    final at = DateTime.parse('2026-10-07T10:00:14Z').millisecondsSinceEpoch;
    expect(thinkingLabel(const AssistantProgress(text: 'Asking GPT OSS 120b · step 2', since: '2026-10-07T10:00:00Z'), at), 'Asking GPT OSS 120b · step 2 · 14s');
    expect(thinkingLabel(null, at, at - 3000), 'Thinking… · 3s');
    expect(thinkingLabel(null, at), 'Thinking…');
    expect(thinkingLabel(const AssistantProgress(text: 'Working', since: 'not a time'), at), 'Working');
    expect(thinkingLabel(const AssistantProgress(text: '   ', since: '2026-10-07T10:00:00Z'), at), 'Thinking… · 14s');
    expect(secondsSince('2026-10-07T10:00:20Z', at), 0, reason: 'a phone clock behind the server never shows negative time');
    expect(secondsSince(null, at), null);
  });

  test('stop before the chat has an id is queued, not dropped, and pressing again does not send twice', () {
    final queued = pressStop(StopPhase.idle, false);
    expect(queued, (phase: StopPhase.queued, send: false));
    expect(pressStop(queued.phase, false), (phase: StopPhase.queued, send: false));
    expect(pressStop(StopPhase.idle, true), (phase: StopPhase.sending, send: true));
    expect(pressStop(const StopPhase.sent(0), true).send, false);
    expect(pressStop(const StopPhase.sent(0), true, true).send, true, reason: 'a stop that did not take can be sent again');
  });

  test('a stop clears when the turn ends, and is stuck if the server keeps running past the grace time', () {
    const sent = StopPhase.sent(1000);
    expect(stopStatus(sent, false, 2000), (phase: StopPhase.idle, stuck: false));
    expect(stopStatus(sent, true, 1000 + stopGraceMs), (phase: sent, stuck: false));
    expect(stopStatus(sent, true, 1001 + stopGraceMs), (phase: sent, stuck: true));
    expect(stopStatus(StopPhase.idle, true, 1000000000000).stuck, false);
  });

  test('send is usable while running only when the turn looks lost', () {
    expect(canSendNow(const ChatState(running: false), stuck: false, unreachable: false), true);
    expect(canSendNow(const ChatState(running: true), stuck: false, unreachable: false), false);
    expect(canSendNow(const ChatState(running: true), stuck: true, unreachable: false), true);
    expect(canSendNow(const ChatState(running: true), stuck: false, unreachable: true), true);
  });
}
