import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDb, type Db } from './db.js';

describe('db session ownership', () => {
  let dir: string;
  let db: Db;
  before(() => {
    dir = mkdtempSync(join(tmpdir(), 'hub-db-test-'));
    db = openDb(dir);
  });
  after(() => rmSync(dir, { recursive: true, force: true }));

  it('another VM cannot take over or alter a session it does not own', () => {
    db.upsertSession({ id: 'sess', vmId: 'vm-a', cwd: '/a', title: 'mine', status: 'idle', accountId: 'default' });
    db.upsertSession({ id: 'sess', vmId: 'vm-b', cwd: '/b', title: 'stolen', status: 'active', accountId: 'default' });
    db.touchSession('sess', 'active', 'vm-b');
    assert.equal(db.listSessionsByVm('vm-b').length, 0);
    const [s] = db.listSessionsByVm('vm-a');
    assert.equal(s.title, 'mine');
    assert.equal(s.status, 'idle');
  });

  it('the owner can still update its own session', () => {
    db.touchSession('sess', 'active', 'vm-a');
    assert.equal(db.listSessionsByVm('vm-a')[0].status, 'active');
  });

  it('a VM cannot rekey another VM\'s messages', () => {
    db.insertMessage({ sessionId: 'tmp-1', vmId: 'vm-a', message: { x: 1 } });
    db.rekeySession('tmp-1', 'hijack', 'vm-b');
    assert.equal(db.listMessages('hijack', 'vm-b').length, 0);
    db.rekeySession('tmp-1', 'real', 'vm-a');
    assert.equal(db.listMessages('real', 'vm-a').length, 1);
  });
});

describe('db auth tokens', () => {
  it('stores only a digest, validates, and revokes', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-test-'));
    const db = openDb(dir);
    const t = db.createAuthToken();
    assert.equal(db.isValidToken(t), true);
    assert.equal(db.isValidToken(t + 'x'), false);
    db.revokeAuthToken(t);
    assert.equal(db.isValidToken(t), false);
    rmSync(dir, { recursive: true, force: true });
  });
});

import { DatabaseSync } from 'node:sqlite';
import { existsSync, statSync } from 'node:fs';

const TOKEN = 'esc_mcp_super_secret_token_value';

describe('db secrets at rest', () => {
  const key = 'a-long-random-secret-for-tests-0123456789';

  it('stores the MCP token encrypted and returns it decrypted', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-enc-'));
    const db = openDb(dir, { encryptionKey: key });
    db.setMcpServer('escanor', 'https://mcp.example.com', TOKEN);
    const raw = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('SELECT token FROM mcp_servers').get() as { token: string };
    assert.equal(raw.token.includes(TOKEN), false);
    assert.equal(db.listMcpServers()[0].token, TOKEN);
    rmSync(dir, { recursive: true, force: true });
  });

  it('migrates a pre-existing plaintext token on open', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-enc-'));
    const plain = openDb(dir); // no key: legacy plaintext storage
    plain.setMcpServer('escanor', 'https://mcp.example.com', TOKEN);
    const upgraded = openDb(dir, { encryptionKey: key });
    const raw = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('SELECT token FROM mcp_servers').get() as { token: string };
    assert.equal(raw.token.includes(TOKEN), false);
    assert.equal(upgraded.listMcpServers()[0].token, TOKEN);
    rmSync(dir, { recursive: true, force: true });
  });

  it('skips an entry it cannot decrypt (key rotated) instead of crashing every send', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-enc-'));
    openDb(dir, { encryptionKey: key }).setMcpServer('escanor', 'https://mcp.example.com', TOKEN);
    const rotated = openDb(dir, { encryptionKey: 'a-different-long-random-secret-9876543210' });
    assert.deepEqual(rotated.listMcpServers(), []);
    rmSync(dir, { recursive: true, force: true });
  });
});

describe('db storage hygiene', () => {
  it('redacts credentials before they are written to the transcript', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-red-'));
    const db = openDb(dir);
    db.insertMessage({
      sessionId: 's', vmId: 'v',
      message: { type: 'permission_request', input: { command: 'curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345" x', headers: { authorization: 'Bearer zzz' } } },
    });
    const text = JSON.stringify(db.listMessages('s', 'v'));
    assert.equal(text.includes('abcdefghijklmnopqrstuvwxyz012345'), false);
    assert.equal(text.includes('Bearer zzz'), false);
    assert.ok(text.includes('curl'));
    rmSync(dir, { recursive: true, force: true });
  });

  it('uses WAL and owner-only permissions on the database', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-wal-'));
    const db = openDb(dir);
    db.insertMessage({ sessionId: 's', vmId: 'v', message: { a: 1 } });
    const mode = new DatabaseSync(join(dir, 'hub.sqlite')).prepare('PRAGMA journal_mode').get() as { journal_mode: string };
    assert.equal(mode.journal_mode, 'wal');
    assert.equal(statSync(join(dir, 'hub.sqlite')).mode & 0o077, 0, 'db file must not be group/world accessible');
    assert.equal(statSync(dir).mode & 0o077, 0, 'data dir must not be group/world accessible');
    assert.ok(existsSync(join(dir, 'hub.sqlite')));
    rmSync(dir, { recursive: true, force: true });
  });

  it('keeps large write bursts cheap (no per-insert fsync)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hub-db-perf-'));
    const db = openDb(dir);
    const t0 = performance.now();
    for (let i = 0; i < 2000; i++) db.insertMessage({ sessionId: 's', vmId: 'v', message: { type: 'assistant', i } });
    const ms = performance.now() - t0;
    assert.ok(ms < 1500, `2000 inserts took ${ms.toFixed(0)}ms`);
    rmSync(dir, { recursive: true, force: true });
  });
});
