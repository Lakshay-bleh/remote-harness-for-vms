import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import { WebSocket } from 'ws';
import type { AgentToHubMessage } from '@remote-harness/shared';
import { openDb } from './db.js';
import { createAgentServer } from './agentServer.js';

const TOKEN = 'test-agent-token';

type Harness = {
  url: string;
  events: AgentToHubMessage[];
  hellos: string[];
  uncaught: Error[];
  throwOnEvent: { value: boolean };
  close: () => Promise<void>;
};

async function start(opts: { pingIntervalMs?: number; maxPayloadBytes?: number } = {}): Promise<Harness> {
  const dir = mkdtempSync(join(tmpdir(), 'agentserver-test-'));
  const db = openDb(dir);
  const events: AgentToHubMessage[] = [];
  const hellos: string[] = [];
  const uncaught: Error[] = [];
  const throwOnEvent = { value: false };

  const onUncaught = (err: Error) => uncaught.push(err);
  process.on('uncaughtException', onUncaught);

  const agentServer = createAgentServer(db, TOKEN, {
    onHello: (_vmId, vmName) => hellos.push(vmName),
    onEvent: (_vmId, msg) => {
      if (throwOnEvent.value) throw new Error('handler blew up');
      events.push(msg);
    },
    onStatusChange: () => {},
  }, opts);

  const http: Server = createServer();
  http.on('upgrade', (req, socket, head) => {
    if (!agentServer.authorize(req)) return socket.destroy();
    agentServer.wss.handleUpgrade(req, socket, head, (ws) => agentServer.wss.emit('connection', ws, req));
  });
  await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
  const port = (http.address() as AddressInfo).port;

  return {
    url: `ws://127.0.0.1:${port}`,
    events,
    hellos,
    uncaught,
    throwOnEvent,
    close: async () => {
      process.off('uncaughtException', onUncaught);
      agentServer.wss.close();
      http.closeAllConnections();
      await new Promise((r) => http.close(r));
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

async function connect(h: Harness): Promise<WebSocket> {
  const ws = new WebSocket(h.url, { headers: { authorization: `Bearer ${TOKEN}` } });
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  return ws;
}

const settle = () => new Promise((r) => setTimeout(r, 100));

const validHello = {
  type: 'hello',
  agentVersion: '1',
  vmName: 'vm-a',
  hostname: 'h',
  accounts: [],
  sessions: [],
};

describe('agent WebSocket frame handling', () => {
  let h: Harness;
  before(async () => {
    h = await start();
  });
  after(async () => {
    await h.close();
  });

  it('survives malformed frames without an uncaught exception, then still handles a valid frame', async () => {
    const ws = await connect(h);

    // Malformed before hello
    ws.send('null');
    ws.send('42');
    ws.send('"str"');
    ws.send('[]');
    ws.send(JSON.stringify({ type: 'hello' })); // no vmName
    ws.send(JSON.stringify({ type: 'hello', vmName: { nested: 1 } }));
    ws.send(JSON.stringify({ type: 'hello', vmName: 'vm-bad', accounts: 'nope', sessions: 5 }));
    await settle();
    assert.deepEqual(h.uncaught.map(String), []);
    assert.deepEqual(h.hellos, [], 'malformed hellos must not register a VM');

    // Valid hello, then malformed events
    ws.send(JSON.stringify(validHello));
    await settle();
    assert.deepEqual(h.hellos, ['vm-a']);

    ws.send(JSON.stringify({ type: 'sdk_message' })); // no sessionId
    ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 7, message: {} }));
    ws.send(JSON.stringify({ type: 'session_created', tempId: 't' })); // missing fields
    ws.send(JSON.stringify({ type: 'permission_request', sessionId: 's' })); // missing requestId/toolName/input
    ws.send(JSON.stringify({ type: 'projects_list', requestId: 'r', projects: 'abc' }));
    ws.send(JSON.stringify({ type: 'totally_unknown' }));
    await settle();
    assert.deepEqual(h.uncaught.map(String), []);
    assert.deepEqual(h.events, [], 'malformed events must be dropped before reaching handlers');

    // Valid frame after garbage still works on the same socket
    const good = { type: 'sdk_message', sessionId: 's1', message: { hi: 1 } };
    ws.send(JSON.stringify(good));
    await settle();
    assert.deepEqual(h.events, [good]);
    ws.close();
  });

  it('keeps the connection usable when an event handler throws', async () => {
    const ws = await connect(h);
    ws.send(JSON.stringify({ ...validHello, vmName: 'vm-b' }));
    await settle();

    h.throwOnEvent.value = true;
    ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 's2', message: {} }));
    await settle();
    assert.deepEqual(h.uncaught.map(String), []);

    h.throwOnEvent.value = false;
    h.events.length = 0;
    ws.send(JSON.stringify({ type: 'session_ended', sessionId: 's2' }));
    await settle();
    assert.equal(h.events.length, 1);
    ws.close();
  });
});

const closeInfo = (ws: WebSocket) => new Promise<{ code: number }>((resolve) => ws.once('close', (code) => resolve({ code })));
const isOpen = (ws: WebSocket) => ws.readyState === WebSocket.OPEN;

describe('agent connection integrity', () => {
  it('ignores a second hello with a different name on the same socket and closes it', async () => {
    const h2 = await start();
    try {
      const ws = await connect(h2);
      const closed = closeInfo(ws);
      ws.send(JSON.stringify({ ...validHello, vmName: 'vm-c' }));
      await settle();
      ws.send(JSON.stringify({ ...validHello, vmName: 'vm-d' }));
      assert.equal((await closed).code, 1008);
      assert.deepEqual(h2.hellos, ['vm-c']);
    } finally {
      await h2.close();
    }
  });

  it('rejects a second live connection claiming the same VM name instead of kicking the first', async () => {
    const h2 = await start();
    try {
      const a = await connect(h2);
      a.send(JSON.stringify({ ...validHello, vmName: 'vm-dup' }));
      await settle();
      const b = await connect(h2);
      const bClosed = closeInfo(b);
      b.send(JSON.stringify({ ...validHello, vmName: 'vm-dup' }));
      assert.equal((await bClosed).code, 1008);
      assert.equal(isOpen(a), true);
      assert.deepEqual(h2.hellos, ['vm-dup']);
      a.close();
    } finally {
      await h2.close();
    }
  });

  it('drops half-open agents (no pong) but keeps responsive ones', async () => {
    const h2 = await start({ pingIntervalMs: 50 });
    try {
      const dead = new WebSocket(h2.url, { headers: { authorization: `Bearer ${TOKEN}` }, autoPong: false });
      await new Promise((r) => dead.once('open', r));
      dead.send(JSON.stringify({ ...validHello, vmName: 'vm-dead' }));
      const live = await connect(h2);
      live.send(JSON.stringify({ ...validHello, vmName: 'vm-live' }));
      const deadClosed = closeInfo(dead);
      await Promise.race([deadClosed, new Promise((r) => setTimeout(r, 1000))]);
      assert.equal(isOpen(dead), false, 'unresponsive agent must be terminated');
      assert.equal(isOpen(live), true, 'responsive agent must stay connected');
      live.close();
    } finally {
      await h2.close();
    }
  });

  it('closes connections that send oversized frames', async () => {
    const h2 = await start({ maxPayloadBytes: 1024 });
    try {
      const ws = await connect(h2);
      const closed = closeInfo(ws);
      ws.send('x'.repeat(4096));
      assert.equal((await closed).code, 1009);
    } finally {
      await h2.close();
    }
  });
});
