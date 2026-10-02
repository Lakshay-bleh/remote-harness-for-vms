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
});
