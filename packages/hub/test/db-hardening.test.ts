// Storage-level guarantees of the multi-tenant database.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, test } from 'node:test';
import { DEFAULT_TENANT, openDb } from '../src/db.ts';

const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'hub-dbh-'));
  dirs.push(d);
  return d;
};
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const KEY = 'a-long-random-secret-for-tests-0123456789';

// ---- a VM can only touch what it owns, even inside its own tenant ----

test('one VM of a tenant cannot overwrite, touch or rekey another VM\'s session', () => {
  const t = openDb(tmp()).for(DEFAULT_TENANT);
  const a = t.upsertVm('vm-a');
  const b = t.upsertVm('vm-b');
  t.upsertSession({ id: 'sess', vmId: a, cwd: '/a', title: 'mine', status: 'idle', accountId: 'default' });
  t.upsertSession({ id: 'sess', vmId: b, cwd: '/b', title: 'stolen', status: 'active', accountId: 'default' });
  t.touchSession('sess', 'active', b);
  assert.equal(t.listSessionsByVm(b).length, 0);
  assert.equal(t.listSessionsByVm(a)[0].status, 'idle');
  t.touchSession('sess', 'active', a);
  assert.equal(t.listSessionsByVm(a)[0].status, 'active');

  t.insertMessage({ sessionId: 'tmp-1', vmId: a, message: { x: 1 } });
  t.rekeySession('tmp-1', 'hijack', b);
  assert.equal(t.listMessages('hijack', 100, b).length, 0);
  t.rekeySession('tmp-1', 'real', a);
  assert.equal(t.listMessages('real', 100, a).length, 1);
});

test('history is capped to the most recent messages, oldest first, scoped to the VM', () => {
  const t = openDb(tmp()).for(DEFAULT_TENANT);
  for (let i = 0; i < 5; i++) t.insertMessage({ sessionId: 's', vmId: 'v1', message: { i } });
  t.insertMessage({ sessionId: 's', vmId: 'other', message: { leak: true } });
  assert.deepEqual(t.listMessages('s', 2, 'v1').map((m) => m.message), [{ i: 3 }, { i: 4 }]);
  assert.equal(t.listMessages('s', 100, 'v1').length, 5);
});

// ---- secrets at rest ----

test('MCP server credentials are encrypted in the file and read back intact', () => {
  const dir = tmp();
  const db = openDb(dir, { encryptionKey: KEY });
  db.for(DEFAULT_TENANT).putMcpServer({ name: 'escanor', url: 'https://mcp.example/', headers: { Authorization: 'Bearer super-secret-header-value' } });
  const raw = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('SELECT config_json FROM mcp_servers').get() as { config_json: string };
  assert.equal(raw.config_json.includes('super-secret-header-value'), false);
  assert.deepEqual(db.for(DEFAULT_TENANT).listMcpServers()[0].headers, { Authorization: 'Bearer super-secret-header-value' });
});

test('plaintext entries from an older hub are encrypted on first open', () => {
  const dir = tmp();
  openDb(dir).for(DEFAULT_TENANT).putMcpServer({ name: 'escanor', url: 'https://mcp.example/', headers: { Authorization: 'Bearer legacy-plain-secret' } });
  const upgraded = openDb(dir, { encryptionKey: KEY });
  const raw = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('SELECT config_json FROM mcp_servers').get() as { config_json: string };
  assert.equal(raw.config_json.includes('legacy-plain-secret'), false);
  assert.equal(upgraded.for(DEFAULT_TENANT).listMcpServers()[0].headers?.Authorization, 'Bearer legacy-plain-secret');
});

test('an entry that cannot be decrypted (key rotated) is skipped, not fatal', () => {
  const dir = tmp();
  openDb(dir, { encryptionKey: KEY }).for(DEFAULT_TENANT).putMcpServer({ name: 'escanor', url: 'https://mcp.example/' });
  assert.deepEqual(openDb(dir, { encryptionKey: 'a-different-long-random-secret-9876543210' }).for(DEFAULT_TENANT).listMcpServers(), []);
});

test('credentials are redacted from stored transcripts', () => {
  const t = openDb(tmp()).for(DEFAULT_TENANT);
  t.insertMessage({
    sessionId: 's', vmId: 'v',
    message: { type: 'permission_request', input: { command: 'curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345" x', headers: { authorization: 'Bearer zzz' } } },
  });
  const text = JSON.stringify(t.listMessages('s', 100, 'v'));
  assert.equal(text.includes('abcdefghijklmnopqrstuvwxyz012345'), false);
  assert.equal(text.includes('Bearer zzz'), false);
  assert.ok(text.includes('curl'));
});

test('the database is WAL, owner-only, and bursts of writes are cheap', () => {
  const dir = tmp();
  const t = openDb(dir).for(DEFAULT_TENANT);
  const t0 = performance.now();
  for (let i = 0; i < 2000; i++) t.insertMessage({ sessionId: 's', vmId: 'v', message: { type: 'assistant', i } });
  assert.ok(performance.now() - t0 < 1500, 'no fsync per insert');
  const mode = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('PRAGMA journal_mode').get() as { journal_mode: string };
  assert.equal(mode.journal_mode, 'wal');
  assert.equal(statSync(join(dir, 'hub.sqlite')).mode & 0o077, 0);
  assert.equal(statSync(dir).mode & 0o077, 0);
});

// ---- API tokens: scoped and expiring ----

test('an MCP-scoped API token is reported with its scope, and an expired token stops working', () => {
  const dir = tmp();
  const db = openDb(dir);
  const t = db.for(DEFAULT_TENANT);
  const mcp = t.createApiToken('escanor', { scope: 'mcp' });
  assert.equal(db.credentialForApiToken(mcp.token)?.scope, 'mcp');
  const full = t.createApiToken('managed');
  assert.equal(db.credentialForApiToken(full.token)?.scope, 'full');
  assert.equal(db.credentialForApiToken(full.token)?.kind, 'api');

  const short = t.createApiToken('short', { ttlSeconds: 60 });
  assert.ok(db.credentialForApiToken(short.token));
  // Age it past its expiry without waiting.
  new DatabaseSync(join(dir, 'hub.sqlite')).prepare('UPDATE api_tokens SET expires_at = ? WHERE id = ?').run(new Date(Date.now() - 5000).toISOString(), short.id);
  assert.equal(db.credentialForApiToken(short.token), null);
  assert.equal(db.tenantForApiToken(short.token), null);
});

test('login tokens are reported as login credentials', () => {
  const db = openDb(tmp());
  const login = db.for(DEFAULT_TENANT).createAuthToken();
  assert.equal(db.credentialForApiToken(login)?.kind, 'login');
  assert.equal(db.credentialForApiToken(login)?.scope, 'full');
});
