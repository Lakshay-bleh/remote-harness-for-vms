import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';

import { searchSessions } from '../src/session-search.js';

// The hosted hub's own tables (src/index.js), in a real SQLite database.
function hub() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE sessions (id TEXT PRIMARY KEY, vm_id TEXT NOT NULL, cwd TEXT, title TEXT, created_at TEXT, last_message_at TEXT, status TEXT, account_id TEXT);
    CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, vm_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL);
  `);
  const exec = (sql: string, ...params: unknown[]) => db.prepare(sql).all(...(params as never[])) as Record<string, unknown>[];
  const session = (id: string, vm: string, title: string, at: string) =>
    db.prepare('INSERT INTO sessions (id, vm_id, title, last_message_at) VALUES (?, ?, ?, ?)').run(id, vm, title, at);
  const say = (session: string, vm: string, message: unknown) =>
    db.prepare('INSERT INTO messages (session_id, vm_id, payload, created_at) VALUES (?, ?, ?, ?)').run(session, vm, JSON.stringify(message), 'now');
  return { exec, session, say };
}

const user = (text: string) => ({ type: 'user', local: true, message: { role: 'user', content: [{ type: 'text', text }] } });
const assistant = (text: string) => ({ type: 'assistant', message: { content: [{ type: 'text', text }] } });

test('finds a chat by what was said in it, with the sentence that matched', () => {
  const h = hub();
  h.session('s1', 'v1', 'Fix CI', '2026-10-09T10:00:00Z');
  h.session('s2', 'v1', 'Write docs', '2026-10-09T11:00:00Z');
  h.say('s1', 'v1', user('why does the build keep failing'));
  h.say('s1', 'v1', assistant('The deployments to Vercel hit a timeout after 45 minutes.'));
  h.say('s2', 'v1', assistant('Here is the README.'));
  const hits = searchSessions(h.exec, 'v1', 'deploy timeout', undefined);
  assert.deepEqual(hits.map((x) => [x.sessionId, x.match]), [['s1', 'words']]);
  assert.equal(hits[0].snippet, 'The deployments to Vercel hit a timeout after 45 minutes.');
});

test('a title match ranks first; tool output, other machines and empty queries do not count', () => {
  const h = hub();
  h.session('a', 'v1', 'Deploy the site', '2026-10-09T10:00:00Z');
  h.session('b', 'v1', 'Misc', '2026-10-09T12:00:00Z');
  h.session('c', 'v2', 'Deploy elsewhere', '2026-10-09T12:00:00Z');
  h.say('b', 'v1', assistant('I will deploy it now.'));
  h.say('b', 'v1', { type: 'user', message: { content: [{ type: 'tool_result', content: 'secret deploy logs' }] } });
  h.say('a', 'v1', { type: 'permission_request', requestId: 'r', toolName: 'Bash', input: { command: 'deploy' } });
  assert.deepEqual(searchSessions(h.exec, 'v1', 'deploy', '10').map((x) => x.sessionId), ['a', 'b']);
  assert.deepEqual(searchSessions(h.exec, 'v1', 'logs', undefined), [], 'tool output is not searched');
  assert.deepEqual(searchSessions(h.exec, 'v1', '   ', undefined), []);
  assert.deepEqual(searchSessions(h.exec, 'v9', 'deploy', undefined), []);
});
