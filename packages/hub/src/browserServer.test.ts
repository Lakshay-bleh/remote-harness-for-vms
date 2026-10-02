import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket } from 'ws';
import { openDb } from './db.js';
import { createBrowserServer } from './browserServer.js';

let cleanup: (() => Promise<void>) | null = null;
afterEach(async () => {
  await cleanup?.();
  cleanup = null;
});

async function start() {
  const dir = mkdtempSync(join(tmpdir(), 'browser-test-'));
  const db = openDb(dir);
  const bs = createBrowserServer(db);
  const http: Server = createServer();
  http.on('upgrade', (req, socket, head) => {
    if (!bs.authorize(req)) return socket.destroy();
    bs.wss.handleUpgrade(req, socket, head, (ws) => bs.wss.emit('connection', ws, req));
  });
  await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
  const url = `ws://127.0.0.1:${(http.address() as AddressInfo).port}`;
  cleanup = async () => {
    bs.wss.close();
    http.closeAllConnections();
    await new Promise((r) => http.close(r));
    rmSync(dir, { recursive: true, force: true });
  };
  return { db, bs, url };
}

const open = (url: string, token: string) =>
  new Promise<WebSocket>((resolve, reject) => {
    const ws = new WebSocket(url, ['escanor.hub.v1', `escanor.auth.${token}`]);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
const closed = (ws: WebSocket) => new Promise<number>((r) => ws.once('close', (code) => r(code)));

describe('browser socket', () => {
  it('rejects unknown tokens', async () => {
    const { url } = await start();
    await assert.rejects(open(url, 'nope'));
  });

  it('closes a revoked client on the periodic sweep, with no broadcast needed', async () => {
    const { db, bs, url } = await start();
    const token = db.createAuthToken();
    const ws = await open(url, token);
    const done = closed(ws);
    db.revokeAuthToken(token);
    bs.closeRevokedSessions();
    assert.equal(await done, 1008);
  });

  it('closes clients that send large frames (browsers only ever send tiny pings)', async () => {
    const { db, url } = await start();
    const ws = await open(url, db.createAuthToken());
    const done = closed(ws);
    ws.send('x'.repeat(200_000));
    assert.equal(await done, 1009);
  });
});
