// Searching a machine's chats by what was said in them: matching rules, ranking, snippets, and the route's boundaries.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import WebSocket from 'ws';
import { DEFAULT_TENANT, openDb } from '../src/db.ts';
import { parseQuery, readableText, SNIPPET_MAX, snippetFor, stem } from '../src/search.ts';

const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'hub-search-'));
  dirs.push(d);
  return d;
};
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const user = (text: string) => ({ type: 'user', message: { role: 'user', content: text } });
const assistant = (...blocks: Record<string, unknown>[]) => ({ type: 'assistant', message: { content: blocks } });
const text = (t: string) => ({ type: 'text', text: t });

/** A tenant with one VM holding the given chats; returns the VM id and the tenant's view. */
function seed(chats: { id: string; title: string; messages?: unknown[] }[]) {
  const t = openDb(tmp()).for(DEFAULT_TENANT);
  const vm = t.upsertVm('vm');
  for (const c of chats) {
    t.upsertSession({ id: c.id, vmId: vm, cwd: '/', title: c.title, status: 'idle', accountId: 'default' });
    for (const m of c.messages ?? []) t.insertMessage({ sessionId: c.id, vmId: vm, message: m });
  }
  return { t, vm };
}

// ---- the matching rules ----

test('query words are folded and lightly stemmed', () => {
  assert.deepEqual(parseQuery('  Café DEPLOYMENTS!  '), { words: ['cafe', 'deployments'], stems: ['cafe', 'deployment'], phrase: 'cafe deployments' });
  assert.equal(parseQuery('  ?!  '), null);
  assert.equal(stem('deploying'), 'deploy');
  assert.equal(stem('deployed'), 'deploy');
  assert.equal(stem('running'), 'run');
  assert.equal(stem('stopped'), 'stop');
  assert.equal(stem('fixes'), 'fix');
  assert.equal(stem('libraries'), 'library');
  assert.equal(stem('class'), 'class');
  assert.equal(stem('bus'), 'bus');
});

test('only what the user and the assistant wrote is searchable, not tool calls or their output', () => {
  assert.equal(readableText(user('hello there')), 'hello there');
  assert.equal(readableText(assistant(text('one'), { type: 'tool_use', input: { cmd: 'secret' } }, text('two'))), 'one\ntwo');
  assert.equal(readableText({ type: 'user', message: { content: [{ type: 'tool_result', content: 'tool output' }] } }), '');
  assert.equal(readableText({ type: 'result', result: 'final' }), '');
  assert.equal(readableText(null), '');
});

test('chats are found by what was said in them, with every word matching as a word prefix', () => {
  const { t, vm } = seed([
    { id: 'a', title: 'Morning chat', messages: [user('How do the deployments work on staging?'), assistant(text('They run from CI.'))] },
    { id: 'b', title: 'Unrelated', messages: [user('let us talk about lunch')] },
    { id: 'c', title: 'Tools only', messages: [assistant({ type: 'tool_use', name: 'Bash', input: { command: 'deploy staging' } })] },
  ]);
  const hits = t.searchSessions(vm, 'deploy staging', 20);
  assert.deepEqual(hits.map((h) => [h.sessionId, h.match]), [['a', 'words']]);
  assert.equal(hits[0].snippet, 'How do the deployments work on staging?');
  // A word must start a word: "ploy" is inside "deployments" but does not match.
  assert.deepEqual(t.searchSessions(vm, 'ploy', 20), []);
  // Every word must match somewhere in the chat, though not necessarily in the same message.
  assert.deepEqual(t.searchSessions(vm, 'staging CI', 20).map((h) => h.sessionId), ['a']);
  assert.deepEqual(t.searchSessions(vm, 'staging lunch', 20), []);
  // Stemmed: "deploying" looks for "deploy…".
  assert.deepEqual(t.searchSessions(vm, 'Deploying', 20).map((h) => h.sessionId), ['a']);
  assert.deepEqual(t.searchSessions(vm, '', 20), []);
});

test('case and accents are ignored on both sides', () => {
  const { t, vm } = seed([
    { id: 'fr', title: 'Notes', messages: [user('Le CAFÉ près de la gare')] },
    { id: 'en', title: 'Cafe list', messages: [] },
  ]);
  assert.deepEqual(t.searchSessions(vm, 'cafe', 20).map((h) => h.sessionId).sort(), ['en', 'fr']);
  assert.deepEqual(t.searchSessions(vm, 'Pres gâre', 20).map((h) => h.sessionId), ['fr']);
});

test('title hits rank above content hits, the exact phrase above scattered words, and newer chats break ties', async () => {
  const { t, vm } = seed([
    { id: 'scattered', title: 'x', messages: [user('the cache is warm'), assistant(text('and the build is slow'))] },
    { id: 'phrase', title: 'y', messages: [user('why is the build cache empty?')] },
    { id: 'titled', title: 'Build cache cleanup', messages: [user('nothing here')] },
  ]);
  const hits = t.searchSessions(vm, 'build cache', 20);
  assert.deepEqual(hits.map((h) => h.sessionId), ['titled', 'phrase', 'scattered']);
  assert.equal(hits[0].match, 'title');
  assert.equal(hits[0].snippet, '', 'no message matched, so there is no snippet');
  assert.ok(hits[0].score > hits[1].score && hits[1].score > hits[2].score);

  const { t: t2, vm: vm2 } = seed([
    { id: 'older', title: 'a', messages: [user('rotate the keys')] },
    { id: 'newer', title: 'b', messages: [user('rotate the keys')] },
  ]);
  await new Promise((r) => setTimeout(r, 5));
  t2.touchSession('newer', 'idle', vm2);
  assert.deepEqual(t2.searchSessions(vm2, 'rotate keys', 20).map((h) => h.sessionId), ['newer', 'older']);
  assert.equal(t2.searchSessions(vm2, 'rotate', 1).length, 1, 'the limit is honoured');
});

test('the snippet is one line from the best message, cut around the match', () => {
  const long = `${'lorem ipsum '.repeat(30)}\n\nthe deployment failed because\nthe token expired ${'dolor sit '.repeat(30)}`;
  const { t, vm } = seed([{ id: 's', title: 't', messages: [user('a deployment happened'), assistant(text(long))] }]);
  const [hit] = t.searchSessions(vm, 'deployment token', 20);
  assert.ok(hit.snippet.length <= SNIPPET_MAX, hit.snippet);
  assert.ok(!hit.snippet.includes('\n'));
  assert.ok(hit.snippet.startsWith('…') && hit.snippet.endsWith('…'), hit.snippet);
  assert.match(hit.snippet, /the deployment failed because the token expired/);
  // The phrase wins over an earlier lone word.
  const q = parseQuery('token expired')!;
  assert.match(snippetFor(`${'token '.repeat(60)} and then the token expired`, q), /the token expired$/);
  assert.equal(snippetFor('short text', q), 'short text');
});

test("another VM's chats, even with the same words, are not searched", () => {
  const t = openDb(tmp()).for(DEFAULT_TENANT);
  const a = t.upsertVm('a');
  const b = t.upsertVm('b');
  t.upsertSession({ id: 'sa', vmId: a, cwd: '/', title: 'ta', status: 'idle', accountId: 'default' });
  t.upsertSession({ id: 'sb', vmId: b, cwd: '/', title: 'tb', status: 'idle', accountId: 'default' });
  t.insertMessage({ sessionId: 'sa', vmId: a, message: user('kubernetes rollout') });
  t.insertMessage({ sessionId: 'sb', vmId: b, message: user('kubernetes rollout') });
  // A message stored under a's session id but from VM b (a misbehaving agent) does not count for a.
  t.insertMessage({ sessionId: 'sa', vmId: b, message: user('helm chart') });
  assert.deepEqual(t.searchSessions(a, 'kubernetes', 20).map((h) => h.sessionId), ['sa']);
  assert.deepEqual(t.searchSessions(a, 'helm', 20), []);
});

// ---- the route ----

test('the search route needs auth, stays within the tenant, and is not taken for a session id', async () => {
  const dir = tmp();
  const port = 19000 + Math.floor(Math.random() * 900);
  const ADMIN = 'admin-secret-for-tests-only-123456';
  const proc: ChildProcess = spawn(process.execPath, ['--import', 'tsx', 'src/index.ts'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: { ...process.env, PORT: String(port), HUB_AGENT_TOKEN: 'legacy-agent-secret-for-tests-only', APP_PASSWORD: 'password-for-tests-only-123456', DATA_DIR: dir, WEB_DIST: dir, HUB_ADMIN_TOKEN: ADMIN },
    stdio: 'ignore',
  });
  const url = `http://127.0.0.1:${port}`;
  const settle = (ms = 250) => new Promise((r) => setTimeout(r, ms));
  try {
    for (let i = 0; i < 80; i++) {
      try {
        await fetch(`${url}/api/vms`);
        break;
      } catch {
        await settle(200);
      }
    }
    const bearer = (tok: string) => ({ authorization: `Bearer ${tok}`, 'content-type': 'application/json' });
    const mint = async (label: string) =>
      (await (await fetch(`${url}/admin/tenants`, { method: 'POST', headers: bearer(ADMIN), body: JSON.stringify({ label }) })).json()) as { agentToken: string; apiToken: string };
    const A = await mint('A');
    const B = await mint('B');

    const ws = new WebSocket(`ws://127.0.0.1:${port}/agent`, { headers: { authorization: `Bearer ${A.agentToken}` } });
    await new Promise((r) => ws.on('open', r));
    ws.send(JSON.stringify({ type: 'hello', agentVersion: '0.5.0', vmName: 'box', hostname: 'h', accounts: [], sessions: [] }));
    await settle();
    ws.send(JSON.stringify({ type: 'session_created', tempId: 't1', sessionId: 'sess-1', cwd: '.', title: 'Monday', accountId: 'default' }));
    ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 'sess-1', message: assistant(text('The migration finished overnight.')) }));
    await settle();

    const vm = ((await (await fetch(`${url}/api/vms`, { headers: bearer(A.apiToken) })).json()) as { id: string }[])[0];
    const search = (tok: string | null, q: string) => fetch(`${url}/api/vms/${vm.id}/sessions/search?q=${encodeURIComponent(q)}`, { headers: tok ? bearer(tok) : {} });

    assert.equal((await search(null, 'migration')).status, 401);
    assert.equal((await search(B.apiToken, 'migration')).status, 404, "another tenant's VM looks like it does not exist");
    const ok = await search(A.apiToken, 'migrations');
    assert.equal(ok.status, 200);
    const [hit, ...rest] = (await ok.json()) as { sessionId: string; snippet: string; score: number; match: string }[];
    assert.equal(rest.length, 0);
    assert.deepEqual({ ...hit, score: 0 }, { sessionId: 'sess-1', snippet: 'The migration finished overnight.', score: 0, match: 'words' });
    assert.ok(hit.score > 0);
    assert.deepEqual(await (await search(A.apiToken, '')).json(), []);
    ws.close();
  } finally {
    proc.kill();
  }
});
