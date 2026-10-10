import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { WebSocketServer, type WebSocket as WS } from 'ws';
import type { AgentToHubMessage } from '@remote-harness/shared';
import { HubConnection } from '../src/wsClient.ts';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fakeHub() {
  const http = createServer();
  const wss = new WebSocketServer({ server: http });
  const received: any[] = [];
  const sockets: WS[] = [];
  wss.on('connection', (ws) => {
    sockets.push(ws);
    ws.on('message', (d) => received.push(JSON.parse(d.toString())));
  });
  await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
  const url = `ws://127.0.0.1:${(http.address() as AddressInfo).port}`;
  return {
    url, received, sockets,
    close: async () => { for (const c of wss.clients) c.terminate(); wss.close(); http.closeAllConnections(); await new Promise((r) => http.close(r)); },
  };
}

const sdk = (n: number): AgentToHubMessage => ({ type: 'sdk_message', sessionId: 's', message: { n } });

describe('HubConnection offline buffering', () => {
  it('replays messages sent while disconnected, after the hello, in order', async () => {
    const hub = await fakeHub();
    let conn!: HubConnection;
    conn = new HubConnection(hub.url, 't', () => {}, () => conn.send({ type: 'hello', agentVersion: '1', vmName: 'v', hostname: 'h', accounts: [], sessions: [] }), { reconnectDelayMs: 20 });
    try {
      conn.send({ type: 'permission_request', sessionId: 's', requestId: 'r1', toolName: 'Bash', input: {} });
      conn.send(sdk(1));
      conn.connect();
      await wait(300);
      assert.deepEqual(hub.received.map((m) => m.type), ['hello', 'permission_request', 'sdk_message']);
    } finally {
      conn.close();
      await hub.close();
    }
  });

  it('buffers across a dropped connection and delivers after reconnect', async () => {
    const hub = await fakeHub();
    const conn = new HubConnection(hub.url, 't', () => {}, () => {}, { reconnectDelayMs: 20 });
    try {
      conn.connect();
      await wait(200);
      for (const s of hub.sockets) s.terminate();
      await wait(30);
      conn.send({ type: 'session_ended', sessionId: 's9' });
      await wait(400);
      assert.ok(hub.received.some((m) => m.type === 'session_ended' && m.sessionId === 's9'));
    } finally {
      conn.close();
      await hub.close();
    }
  });

  it('drops a silent connection and reconnects when pongs stop (network changed under it)', async () => {
    // A hub that never answers pings looks exactly like a half-open TCP socket after sleep or a Wi-Fi change:
    // nothing ever emits 'close', so without a pong deadline the agent stays "connected" to nothing forever.
    const http = createServer();
    const wss = new WebSocketServer({ server: http, autoPong: false });
    let connections = 0;
    wss.on('connection', () => { connections++; });
    await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
    let opens = 0;
    const conn = new HubConnection(`ws://127.0.0.1:${(http.address() as AddressInfo).port}`, 't', () => {}, () => { opens++; },
      { reconnectDelayMs: 20, pingIntervalMs: 50, pongTimeoutMs: 120 });
    try {
      conn.connect();
      await wait(600);
      assert.ok(opens >= 2, `expected a reconnect after missed pongs, got ${opens} open(s)`);
      assert.ok(connections >= 2);
    } finally {
      conn.close();
      for (const c of wss.clients) c.terminate();
      wss.close(); http.closeAllConnections(); await new Promise((r) => http.close(r));
    }
  });

  it('keeps a healthy connection open while pongs arrive', async () => {
    const hub = await fakeHub();
    let opens = 0;
    const conn = new HubConnection(hub.url, 't', () => {}, () => { opens++; }, { reconnectDelayMs: 20, pingIntervalMs: 50, pongTimeoutMs: 120 });
    try {
      conn.connect();
      await wait(600);
      assert.equal(opens, 1);
    } finally {
      conn.close();
      await hub.close();
    }
  });

  it('is bounded and sheds streaming sdk_messages before critical events', () => {
    const conn = new HubConnection('ws://127.0.0.1:1', 't', () => {}, () => {}, { maxBuffered: 3 });
    conn.send({ type: 'permission_request', sessionId: 's', requestId: 'r', toolName: 'Bash', input: {} });
    for (let i = 0; i < 10; i++) conn.send(sdk(i));
    conn.send({ type: 'session_ended', sessionId: 's' });
    const kinds = conn.bufferedForTest().map((m) => m.type);
    assert.equal(kinds.length, 3);
    assert.ok(kinds.includes('permission_request'));
    assert.ok(kinds.includes('session_ended'));
  });

  it('sends again what a silent (half-open) connection never confirmed, after the new hello', async () => {
    // The first connection swallows everything and never pongs: like a socket whose network vanished. What was written
    // to it must reach the next connection; nothing is lost because the old socket "accepted" the bytes.
    const http = createServer();
    const wss = new WebSocketServer({ server: http, autoPong: false });
    const perConnection: any[][] = [];
    wss.on('connection', (ws) => {
      const got: any[] = [];
      perConnection.push(got);
      ws.on('message', (d) => got.push(JSON.parse(d.toString())));
      if (perConnection.length > 1) ws.on('ping', () => ws.pong()); // the new connection is healthy
    });
    await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
    let conn!: HubConnection;
    conn = new HubConnection(`ws://127.0.0.1:${(http.address() as AddressInfo).port}`, 't', () => {},
      () => conn.send({ type: 'hello', agentVersion: '1', vmName: 'v', hostname: 'h', accounts: [], sessions: [] }),
      { reconnectDelayMs: 20, pingIntervalMs: 40, pongTimeoutMs: 150 });
    try {
      conn.connect();
      await wait(80);
      conn.send(sdk(1));
      conn.send({ type: 'permission_request', sessionId: 's', requestId: 'r1', toolName: 'Bash', input: {} });
      conn.send({ type: 'sdk_partial', sessionId: 's', text: 'typing' });
      await wait(700);
      assert.ok(perConnection.length >= 2, 'reconnected');
      const second = perConnection[1].map((m) => m.type);
      assert.deepEqual(second.slice(0, 3), ['hello', 'sdk_message', 'permission_request']);
      assert.ok(!second.includes('sdk_partial'), 'live text is never replayed');
    } finally {
      conn.close();
      for (const c of wss.clients) c.terminate();
      wss.close(); http.closeAllConnections(); await new Promise((r) => http.close(r));
    }
  });

  it('forgets what a pong confirmed, so a healthy connection replays nothing', async () => {
    const hub = await fakeHub();
    const conn = new HubConnection(hub.url, 't', () => {}, () => {}, { reconnectDelayMs: 20, pingIntervalMs: 40, pongTimeoutMs: 500 });
    try {
      conn.connect();
      await wait(80);
      conn.send(sdk(1));
      conn.send(sdk(2));
      await wait(200);
      assert.equal(conn.unconfirmedForTest().length, 0);
    } finally {
      conn.close();
      await hub.close();
    }
  });

  it('drops live text while offline instead of buffering it', () => {
    const conn = new HubConnection('ws://127.0.0.1:1', 't', () => {}, () => {});
    conn.send({ type: 'sdk_partial', sessionId: 's', text: 'abc' });
    assert.equal(conn.bufferedForTest().length, 0);
  });
});
