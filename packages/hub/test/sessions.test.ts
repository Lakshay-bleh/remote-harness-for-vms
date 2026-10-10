// Chats on the self-hosted hub: mode/model/effort go with each message, the temporary id a chat started under is listed,
// messages come a page at a time, and a chat can be renamed and deleted. Boots the real hub.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import WebSocket from 'ws';

const json = { 'content-type': 'application/json' };
const settle = (ms = 250) => new Promise((r) => setTimeout(r, ms));
const ADMIN = 'admin-secret-for-tests-only-123456';
const admin = { authorization: `Bearer ${ADMIN}`, ...json };
const bearer = (t: string) => ({ authorization: `Bearer ${t}`, ...json });

let dir: string;
let proc: ChildProcess;
let url: string;
let port: number;
type Tenant = { id: string; agentToken: string; apiToken: string };
type Machine = { id: string; vmName: string; agentToken: string; apiToken: string; expiresAt: string };
let A: Tenant, B: Tenant;

before(async () => {
  dir = mkdtempSync(join(tmpdir(), 'hub-sessions-'));
  port = 19900 + Math.floor(Math.random() * 90);
  proc = spawn(process.execPath, ['--import', 'tsx', 'src/index.ts'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: { ...process.env, PORT: String(port), HUB_AGENT_TOKEN: 'legacy-agent-secret-for-tests-only', APP_PASSWORD: 'password-for-tests-only-123456', DATA_DIR: dir, WEB_DIST: dir, HUB_ADMIN_TOKEN: ADMIN, HUB_MACHINE_MIN_TTL_SECONDS: '1' },
    stdio: ['ignore', 'ignore', process.env.HUB_TEST_STDERR ? 'inherit' : 'ignore'],
  });
  url = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 80; i++) {
    try {
      await fetch(`${url}/api/vms`);
      break;
    } catch {
      await settle(200);
    }
  }
  A = await (await fetch(`${url}/admin/tenants`, { method: 'POST', headers: admin, body: JSON.stringify({ label: 'A' }) })).json();
  B = await (await fetch(`${url}/admin/tenants`, { method: 'POST', headers: admin, body: JSON.stringify({ label: 'B' }) })).json();
});
after(() => {
  proc?.kill();
  rmSync(dir, { recursive: true, force: true });
});


function agent(token: string, vmName: string) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/agent`, { headers: { authorization: `Bearer ${token}` } });
  const inbox: any[] = [];
  ws.on('message', (d) => inbox.push(JSON.parse(d.toString())));
  const ready = new Promise<void>((res) => ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'hello', agentVersion: '0.5.0', vmName, hostname: 'h', accounts: [], sessions: [] }));
    res();
  }));
  return { ws, inbox, ready, send: (m: unknown) => ws.send(JSON.stringify(m)) };
}

test('a chat: choices reach the machine, the temp id is listed, pages of messages, rename, delete', async () => {
  const a = agent(A.agentToken, 'box');
  await a.ready;
  await settle();
  const api = (path: string, init: RequestInit = {}) => fetch(`${url}/api${path}`, { ...init, headers: bearer(A.apiToken) });
  const vms = await (await api('/vms')).json();
  const vm = vms.find((v: { name: string }) => v.name === 'box').id;

  const started = await api(`/vms/${vm}/sessions`, { method: 'POST', body: JSON.stringify({ text: 'hi', permissionMode: 'auto', model: 'claude-opus-4-8', effort: 'high' }) });
  assert.equal(started.status, 202);
  const { tempId } = await started.json();
  await settle();
  const input = a.inbox.find((m) => m.type === 'user_input');
  assert.deepEqual([input.tempId, input.permissionMode, input.model, input.effort], [tempId, 'auto', 'claude-opus-4-8', 'high']);

  a.send({ type: 'session_created', tempId, sessionId: 'real-1', cwd: '/w', title: 'hi', accountId: 'default' });
  for (let i = 0; i < 3; i++) a.send({ type: 'sdk_message', sessionId: 'real-1', message: { type: 'assistant', n: i } });
  await settle();
  const sessions = await (await api(`/vms/${vm}/sessions`)).json();
  assert.equal(sessions[0].id, 'real-1');
  assert.equal(sessions[0].tempId, tempId);

  const sent = await api(`/vms/${vm}/sessions/real-1/messages`, { method: 'POST', body: JSON.stringify({ text: 'more', permissionMode: 'nonsense', effort: '' }) });
  assert.equal(sent.status, 202);
  await settle();
  const next = a.inbox.filter((m) => m.type === 'user_input').at(-1);
  assert.equal('permissionMode' in next, false, 'an unknown mode is left out, the message still goes');
  assert.equal(next.effort, null);

  const all = await (await api(`/vms/${vm}/sessions/real-1/messages`)).json();
  assert.equal(all.length, 5); // hi, 3 replies, more
  const newer = await (await api(`/vms/${vm}/sessions/real-1/messages?after=${all[2].id}`)).json();
  assert.deepEqual(newer.map((m: { id: number }) => m.id), all.slice(3).map((m: { id: number }) => m.id));
  const viaTemp = await (await api(`/vms/${vm}/sessions/${tempId}/messages?limit=2`)).json();
  assert.deepEqual(viaTemp.map((m: { id: number }) => m.id), all.slice(3).map((m: { id: number }) => m.id));

  assert.equal((await api(`/vms/${vm}/sessions/real-1`, { method: 'PATCH', body: JSON.stringify({ title: '  ' }) })).status, 400);
  assert.equal((await api(`/vms/${vm}/sessions/real-1`, { method: 'PATCH', body: JSON.stringify({ title: 'Renamed' }) })).status, 200);
  assert.equal((await (await api(`/vms/${vm}/sessions`)).json())[0].title, 'Renamed');

  assert.equal((await api(`/vms/${vm}/sessions/real-1`, { method: 'DELETE' })).status, 200);
  assert.deepEqual(await (await api(`/vms/${vm}/sessions`)).json(), []);
  assert.deepEqual(await (await api(`/vms/${vm}/sessions/real-1/messages`)).json(), []);
  assert.equal((await api(`/vms/${vm}/sessions/real-1`, { method: 'DELETE' })).status, 404);

  // Another tenant cannot touch it.
  const other = await fetch(`${url}/api/vms/${vm}/sessions/real-1`, { method: 'DELETE', headers: bearer(B.apiToken) });
  assert.ok(other.status === 404 || other.status === 403, `got ${other.status}`);
  a.ws.close();
});
