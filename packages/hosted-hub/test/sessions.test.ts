import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';

import { SESSIONS_SCHEMA, deleteSession, listMessages, listSessions, messageQuery, recordAlias, renameSession, resolveSession, runChoices } from '../src/sessions.js';

// The hosted hub's own tables (src/index.js), in a real SQLite database.
function hub() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE sessions (id TEXT PRIMARY KEY, vm_id TEXT NOT NULL, cwd TEXT, title TEXT, created_at TEXT, last_message_at TEXT, status TEXT, account_id TEXT);
    CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, vm_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL);
  `);
  db.exec(SESSIONS_SCHEMA);
  const exec = (sql: string, ...params: unknown[]) => db.prepare(sql).all(...(params as never[])) as Record<string, unknown>[];
  const session = (id: string, vm: string, title: string, at = '2026-10-10T10:00:00Z') =>
    db.prepare('INSERT INTO sessions (id, vm_id, cwd, title, created_at, last_message_at, status, account_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').run(id, vm, '/w', title, at, at, 'idle', 'default');
  const say = (session: string, vm: string, n: number) => {
    for (let i = 0; i < n; i++) db.prepare('INSERT INTO messages (session_id, vm_id, payload, created_at) VALUES (?, ?, ?, ?)').run(session, vm, JSON.stringify({ type: 'assistant', n: i }), 'now');
  };
  return { exec, session, say };
}

test('a chat lists the temporary id it started under, so an app that missed session_created can match it', () => {
  const h = hub();
  h.session('real-1', 'v1', 'Fix CI');
  h.session('real-2', 'v1', 'Docs', '2026-10-10T09:00:00Z');
  recordAlias(h.exec, 'temp-1', 'real-1');
  recordAlias(h.exec, 'same', 'same'); // a terminal chat: no alias
  const list = listSessions(h.exec, 'v1');
  assert.deepEqual(list.map((s) => [s.id, s.tempId]), [['real-1', 'temp-1'], ['real-2', undefined]]);
  assert.equal('tempId' in list[1], false);
  assert.equal(resolveSession(h.exec, 'temp-1'), 'real-1');
  assert.equal(resolveSession(h.exec, 'real-2'), 'real-2');
});

test('messages come a page at a time: the newest, only newer ones, or the page before', () => {
  const h = hub();
  h.session('s', 'v1', 'Long');
  h.say('s', 'v1', 10);
  h.say('other', 'v1', 3);
  const ids = (rows: { id: number }[]) => rows.map((r) => r.id);
  assert.deepEqual(ids(listMessages(h.exec, 's') as never), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.deepEqual(ids(listMessages(h.exec, 's', { limit: 3 }) as never), [8, 9, 10]);
  assert.deepEqual(ids(listMessages(h.exec, 's', { after: 7 }) as never), [8, 9, 10]);
  assert.deepEqual(ids(listMessages(h.exec, 's', { after: 10 }) as never), []);
  assert.deepEqual(ids(listMessages(h.exec, 's', { before: 8, limit: 3 }) as never), [5, 6, 7]);
  assert.deepEqual((listMessages(h.exec, 's', { limit: 1 })[0] as { message: unknown }).message, { type: 'assistant', n: 9 });
});

test('?limit/after/before are read as whole numbers, and the limit is kept sane', () => {
  const q = (s: string) => messageQuery(new URLSearchParams(s));
  assert.deepEqual(q(''), { limit: 2000, after: undefined, before: undefined });
  assert.deepEqual(q('limit=300&after=42'), { limit: 300, after: 42, before: undefined });
  assert.deepEqual(q('limit=999999&before=7'), { limit: 5000, after: undefined, before: 7 });
  assert.deepEqual(q('limit=abc&after=-1&before=1e3'), { limit: 2000, after: undefined, before: undefined });
});

test('rename and delete touch only that chat on that machine', () => {
  const h = hub();
  h.session('s1', 'v1', 'Old');
  h.session('s2', 'v2', 'Other machine');
  h.say('s1', 'v1', 2);
  h.say('s2', 'v2', 2);
  recordAlias(h.exec, 't1', 's1');
  assert.equal(renameSession(h.exec, 'v1', 's1', 'New'), true);
  assert.equal(renameSession(h.exec, 'v1', 's2', 'Nope'), false, 'another machine\'s chat');
  assert.equal(listSessions(h.exec, 'v1')[0].title, 'New');
  assert.equal(deleteSession(h.exec, 'v1', 's2'), false);
  assert.equal(deleteSession(h.exec, 'v1', 's1'), true);
  assert.deepEqual(listSessions(h.exec, 'v1'), []);
  assert.deepEqual(listMessages(h.exec, 's1'), []);
  assert.equal(resolveSession(h.exec, 't1'), 't1', 'the alias goes too');
  assert.equal(listMessages(h.exec, 's2').length, 2);
  assert.equal(deleteSession(h.exec, 'v1', 's1'), false, 'a second delete finds nothing');
});

test('mode, model and effort that come with a message: known values only', () => {
  assert.deepEqual(runChoices({ permissionMode: 'auto', model: 'claude-opus-4-8', effort: 'high' }), { permissionMode: 'auto', model: 'claude-opus-4-8', effort: 'high' });
  assert.deepEqual(runChoices({ permissionMode: 'yolo', model: 5, effort: 'huge' }), {});
  assert.deepEqual(runChoices({ model: '', effort: '' }), { model: '', effort: null });
  assert.deepEqual(runChoices({ effort: null }), { effort: null });
  assert.deepEqual(runChoices(null), {});
});
