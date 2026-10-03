import assert from 'node:assert/strict';
import { test } from 'node:test';
import { EMPTY_META, cleanName, matches, organise, parseMeta, prune, rename, toggleArchived, togglePinned, type ChatItem } from './chatList';

const NOW = Date.parse('2026-10-03T15:00:00');
const at = (daysAgo: number, hour = 9) => new Date(new Date(NOW).setHours(hour, 0, 0, 0) - daysAgo * 86_400_000).toISOString();
const chats: ChatItem[] = [
  { id: 'a', title: 'Fix the failing build', updated_at: at(0, 10), created_at: at(0, 9) },
  { id: 'b', title: 'Deploy to Vercel', updated_at: at(1), created_at: at(1) },
  { id: 'c', title: 'Cost report', updated_at: at(4), created_at: at(4) },
  { id: 'd', title: 'Old idea', updated_at: at(20), created_at: at(20) },
  { id: 'e', title: 'Ancient', updated_at: at(90), created_at: at(90) },
];

test('chats are grouped by when they were last used, newest first', () => {
  const s = organise(chats, EMPTY_META, { now: NOW });
  assert.deepEqual(s.map((x) => x.label), ['Today', 'Yesterday', 'Previous 7 days', 'Previous 30 days', 'Older']);
  assert.deepEqual(s.map((x) => x.rows.map((r) => r.id)), [['a'], ['b'], ['c'], ['d'], ['e']]);
});

test('pinned chats lead, in the order they were pinned, and do not repeat below', () => {
  let m = togglePinned(EMPTY_META, 'd');
  m = togglePinned(m, 'b');
  const s = organise(chats, m, { now: NOW });
  assert.equal(s[0].label, 'Pinned');
  assert.deepEqual(s[0].rows.map((r) => r.id), ['b', 'd']);
  assert.ok(!s.slice(1).some((x) => x.rows.some((r) => r.id === 'b' || r.id === 'd')));
  assert.deepEqual(togglePinned(m, 'b').pinned, ['d']); // a second tap unpins
});

test('a name the person gave replaces the generated title, and clearing it brings the title back', () => {
  const m = rename(EMPTY_META, 'a', '  My   build   fix ');
  assert.equal(organise(chats, m, { now: NOW })[0].rows[0].name, 'My build fix');
  assert.equal(organise(chats, rename(m, 'a', '   '), { now: NOW })[0].rows[0].name, 'Fix the failing build');
  assert.equal(cleanName('x'.repeat(200)).length, 80);
});

test('archived chats are hidden unless asked for, and archiving unpins', () => {
  const m = toggleArchived(togglePinned(EMPTY_META, 'c'), 'c');
  assert.equal(m.pinned.length, 0);
  assert.ok(!organise(chats, m, { now: NOW }).some((s) => s.rows.some((r) => r.id === 'c')));
  const withArchive = organise(chats, m, { now: NOW, showArchived: true });
  assert.deepEqual(withArchive[withArchive.length - 1].rows.map((r) => r.id), ['c']);
});

test('search matches every word in any order, ignores case and accents, and looks through archived chats', () => {
  assert.ok(matches('Fix the failing build', 'BUILD fix'));
  assert.ok(matches('Café report', 'cafe'));
  assert.ok(!matches('Fix the failing build', 'deploy'));
  const m = toggleArchived(EMPTY_META, 'c');
  const hits = organise(chats, m, { now: NOW, query: 'report' });
  assert.deepEqual(hits[0].rows.map((r) => r.id), ['c']);
  assert.deepEqual(organise(chats, m, { now: NOW, query: 'nothing like this' }), []);
  assert.equal(organise(chats, rename(EMPTY_META, 'e', 'Launch plan'), { now: NOW, query: 'launch' })[0].rows[0].id, 'e'); // by the name the person sees
});

test('stored organisation survives damage, and forgets chats that are gone', () => {
  assert.deepEqual(parseMeta('{oops'), EMPTY_META);
  assert.deepEqual(parseMeta(JSON.stringify({ pinned: ['a', 5, 'a'], titles: { a: ' Hi ', b: 7, c: '' }, archived: 'no' })), { pinned: ['a'], titles: { a: 'Hi' }, archived: [] });
  const m = { pinned: ['a', 'gone'], titles: { a: 'A', gone: 'G' }, archived: ['gone'] };
  assert.deepEqual(prune(m, ['a']), { pinned: ['a'], titles: { a: 'A' }, archived: [] });
  assert.equal(prune(m, ['a', 'gone']), m); // nothing to forget: same object, so no needless save
});
