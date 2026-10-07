import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addOptimisticMessage,
  applyMessages,
  canSendNow,
  describeUsage,
  dropOptimisticMessages,
  emptyChat,
  isThinking,
  markAnswered,
  pollDelayMs,
  pressStop,
  secondsSince,
  STOP_GRACE_MS,
  stopStatus,
  thinkingLabel,
  toDisplay,
} from '../src/escanor.ts';

const res = (over: Record<string, unknown> = {}) => ({ items: [], approvals: [], running: false, pending: 0, last_id: 0, ...over }) as never;
const user = (id: number, text: string) => ({ id, kind: 'user', text });
const assistant = (id: number, text: string) => ({ id, kind: 'assistant', text });
const activity = (id: number, text: string) => ({ id, kind: 'activity', text });
const approval = (id: number, request_id: string, status = 'pending') =>
  ({ id, kind: 'approval', request_id, status, title: 'Run a command', detail: 'ls', risk: 'normal', raw: 'ls' }) as never;

test('a message shows at once, then is replaced (not duplicated) by the real one', () => {
  let s = addOptimisticMessage(emptyChat, 'hello');
  assert.equal(toDisplay(s).length, 1);
  assert.equal(s.running, true);
  s = applyMessages(s, res({ items: [user(1, 'hello')], running: true, last_id: 1 }));
  assert.deepEqual(toDisplay(s).map((b) => b.type), ['user']);
  assert.equal((toDisplay(s)[0] as { optimistic?: boolean }).optimistic, undefined);
});

test('two identical messages sent in a row stay two', () => {
  let s = addOptimisticMessage(addOptimisticMessage(emptyChat, 'again'), 'again');
  s = applyMessages(s, res({ items: [user(1, 'again')], running: true, last_id: 1 }));
  assert.equal(toDisplay(s).filter((b) => b.type === 'user').length, 2, 'one confirmed, one still pending');
  s = applyMessages(s, res({ items: [user(2, 'again')], running: true, last_id: 2 }));
  assert.equal(toDisplay(s).filter((b) => b.type === 'user').length, 2);
  assert.ok(toDisplay(s).every((b) => !('optimistic' in b) || !b.optimistic));
});

test('a failed send takes the optimistic message back', () => {
  const s = dropOptimisticMessages(addOptimisticMessage(emptyChat, 'oops'));
  assert.deepEqual(s.items, []);
  assert.equal(s.running, false);
});

test('applying the same response twice changes nothing', () => {
  const r = res({ items: [user(1, 'a'), assistant(2, 'b')], last_id: 2 });
  const once = applyMessages(emptyChat, r);
  const twice = applyMessages(once, r);
  assert.deepEqual(twice.items, once.items);
  assert.equal(twice.lastId, 2);
});

test('polls append only what is new', () => {
  let s = applyMessages(emptyChat, res({ items: [user(1, 'a')], last_id: 1, running: true }));
  s = applyMessages(s, res({ items: [assistant(2, 'b')], last_id: 2, running: false }));
  assert.deepEqual(s.items.map((i) => i.kind), ['user', 'assistant']);
  assert.equal(s.running, false);
  assert.equal(s.lastId, 2, 'the cursor covers rows the person never sees too');
  s = applyMessages(s, res({ items: [], last_id: 9 }));
  assert.equal(s.lastId, 9);
});

test("an answer updates the question the page already has", () => {
  let s = applyMessages(emptyChat, res({ items: [user(1, 'x'), approval(2, 'r1')], last_id: 2, running: true, pending: 1 }));
  assert.equal((toDisplay(s)[1] as { item: { status: string } }).item.status, 'pending');
  s = applyMessages(s, res({ items: [], approvals: [{ request_id: 'r1', status: 'allowed' }], last_id: 2, running: true, pending: 0 }));
  assert.equal((toDisplay(s)[1] as { item: { status: string } }).item.status, 'allowed');
});

test('clicking Continue reflects immediately, and only once', () => {
  let s = applyMessages(emptyChat, res({ items: [approval(2, 'r1')], last_id: 2, running: true, pending: 1 }));
  s = markAnswered(s, 'r1', true);
  assert.equal(s.pending, 0);
  assert.equal((toDisplay(s)[0] as { item: { status: string } }).item.status, 'allowed');
  s = markAnswered(s, 'r1', false);
  assert.equal((toDisplay(s)[0] as { item: { status: string } }).item.status, 'allowed', 'an answered question is not re-answered');
  assert.equal(s.pending, 0, 'and pending never goes negative');
});

test('repeated activity collapses to one quiet line, and only the latest pulses', () => {
  const items = [user(1, 'q'), activity(2, 'Checking which services are available'), activity(3, 'Checking which services are available'), activity(4, 'Using Escanor — GitHub: list repos')];
  const running = toDisplay(applyMessages(emptyChat, res({ items, last_id: 4, running: true })));
  assert.deepEqual(running.map((b) => b.type), ['user', 'activity', 'activity']);
  assert.deepEqual(running.filter((b) => b.type === 'activity').map((b) => (b as { live: boolean }).live), [false, true]);
  const finished = toDisplay(applyMessages(emptyChat, res({ items, last_id: 4, running: false })));
  assert.ok(finished.every((b) => b.type !== 'activity' || !b.live), 'nothing pulses once it is done');
});

test('the turn-finished marker and expired questions are not drawn', () => {
  const s = applyMessages(emptyChat, res({ items: [user(1, 'x'), approval(2, 'r1', 'expired'), { id: 3, kind: 'done' }, assistant(4, 'ok')], last_id: 4 }));
  assert.deepEqual(toDisplay(s).map((b) => b.type), ['user', 'assistant']);
});

test('the thinking indicator is for waiting on the assistant, never on the person', () => {
  assert.equal(isThinking(addOptimisticMessage(emptyChat, 'hi')), true);
  const asking = applyMessages(emptyChat, res({ items: [user(1, 'x'), approval(2, 'r1')], last_id: 2, running: true, pending: 1 }));
  assert.equal(isThinking(asking), false, 'waiting for the person to answer is not "thinking"');
  const talking = applyMessages(emptyChat, res({ items: [user(1, 'x'), assistant(2, 'here you go')], last_id: 2, running: true }));
  assert.equal(isThinking(talking), false);
  assert.equal(isThinking(emptyChat), false);
});

test('polling is quick while working and patient when idle', () => {
  assert.equal(pollDelayMs({ ...emptyChat, running: true }), 700);
  assert.equal(pollDelayMs({ ...emptyChat, pending: 1 }), 1500);
  assert.ok(pollDelayMs(emptyChat) >= 5000);
});

// ---- markdown ----

test('usage is described in messages, not dollars, and warns before the limit', () => {
  const at = (messages: number, tokens = 0) => describeUsage({ messages_today: messages, message_limit: 200, today: { tokens } });
  assert.deepEqual(at(12, 45_300), { messages: '12 of 200 messages today', tokens: '45.3k tokens', ratio: 0.06, level: 'ok' });
  assert.equal(at(160).level, 'warn');
  assert.equal(at(200).level, 'full');
  assert.equal(at(999).ratio, 1, 'never shows more than full');
  assert.equal(at(3).tokens, null, 'no tokens, nothing to say');
  const unlimited = describeUsage({ messages_today: 1, message_limit: null, today: { tokens: 2_000_000 } });
  assert.deepEqual(unlimited, { messages: '1 message today', tokens: '2M tokens', ratio: null, level: 'ok' });
  assert.equal(JSON.stringify(unlimited).includes('$'), false);
});

// ---------------------------------------------------------------------------- notices, progress, stopping

const notice = (id: number, text: string) => ({ id, kind: 'notice', text });

test('a notice is drawn as its own quiet line, and a stopped turn ends on it', () => {
  let s = applyMessages(emptyChat, res({ items: [user(1, 'deploy'), activity(2, 'Checking'), notice(3, 'Stopped.')], running: false, last_id: 3 }));
  assert.deepEqual(toDisplay(s).map((b) => b.type), ['user', 'activity', 'notice']);
  assert.equal((toDisplay(s)[2] as { text: string }).text, 'Stopped.');
  assert.equal(isThinking(s), false);
  s = applyMessages(emptyChat, res({ items: [user(1, 'hi'), notice(2, 'A was not available, so B is answering.')], running: true, last_id: 2 }));
  assert.equal(isThinking(s), true, 'a notice mid-turn is still waiting on the answer');
});

test('progress is kept while running, dropped when the turn ends, and absent from older servers', () => {
  const progress = { text: 'Asking GPT OSS 120b · step 2', since: '2026-10-07T10:00:00Z', step: 2 };
  let s = applyMessages(emptyChat, res({ items: [user(1, 'hi')], running: true, last_id: 1, progress }));
  assert.deepEqual(s.progress, progress);
  s = applyMessages(s, res({ running: false, last_id: 1, progress }));
  assert.equal(s.progress, null);
  s = applyMessages(emptyChat, res({ running: true }));
  assert.equal(s.progress, null);
  assert.equal(dropOptimisticMessages({ ...s, progress }).progress, null);
});

test('the thinking line says what it is doing and for how long', () => {
  const at = Date.parse('2026-10-07T10:00:14Z');
  assert.equal(thinkingLabel({ text: 'Asking GPT OSS 120b · step 2', since: '2026-10-07T10:00:00Z' }, at), 'Asking GPT OSS 120b · step 2 · 14s');
  assert.equal(thinkingLabel(null, at, at - 3000), 'Thinking… · 3s');
  assert.equal(thinkingLabel(null, at), 'Thinking…');
  assert.equal(thinkingLabel({ text: 'Working', since: 'not a time' }, at), 'Working');
  assert.equal(secondsSince('2026-10-07T10:00:20Z', at), 0, 'a phone clock behind the server never shows negative time');
});

test('stop before the chat has an id is queued, not dropped, and pressing again does not send twice', () => {
  const queued = pressStop({ kind: 'idle' }, false);
  assert.deepEqual(queued, { phase: { kind: 'queued' }, send: false });
  assert.deepEqual(pressStop(queued.phase, false), { phase: { kind: 'queued' }, send: false });
  assert.deepEqual(pressStop({ kind: 'idle' }, true), { phase: { kind: 'sending' }, send: true });
  assert.equal(pressStop({ kind: 'sent', at: 0 }, true).send, false);
  assert.equal(pressStop({ kind: 'sent', at: 0 }, true, true).send, true, 'a stop that did not take can be sent again');
});

test('a stop clears when the turn ends, and is stuck if the server keeps running past the grace time', () => {
  const sent = { kind: 'sent', at: 1000 } as const;
  assert.deepEqual(stopStatus(sent, false, 2000), { phase: { kind: 'idle' }, stuck: false });
  assert.deepEqual(stopStatus(sent, true, 1000 + STOP_GRACE_MS), { phase: sent, stuck: false });
  assert.deepEqual(stopStatus(sent, true, 1001 + STOP_GRACE_MS), { phase: sent, stuck: true });
  assert.equal(stopStatus({ kind: 'idle' }, true, 1e12).stuck, false);
});

test('send is usable while running only when the turn looks lost', () => {
  assert.equal(canSendNow({ running: false }, { stuck: false, unreachable: false }), true);
  assert.equal(canSendNow({ running: true }, { stuck: false, unreachable: false }), false);
  assert.equal(canSendNow({ running: true }, { stuck: true, unreachable: false }), true);
  assert.equal(canSendNow({ running: true }, { stuck: false, unreachable: true }), true);
});
