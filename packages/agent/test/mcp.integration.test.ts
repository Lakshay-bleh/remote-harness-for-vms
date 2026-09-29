// Drives the real SessionManager, the real Agent SDK and a real Claude Code process. Only the model
// (a fake Messages API) and the MCP server (a mock that records what it receives) are stand-ins,
// so this proves the property the feature exists for: the tool is there, and it is callable.
//
// Slow (each turn starts a Claude Code process), so it is not part of `npm test`:
//   npm run test:integration
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import type { AgentToHubMessage, ManagedMcpServer } from '@remote-harness/shared';
import { SessionManager } from '../src/sessionManager.ts';
import { startFakeAnthropic } from './helpers/fakeAnthropic.ts';
import { startMockMcp } from './helpers/mockMcp.ts';

let root: string;
let api: Awaited<ReturnType<typeof startFakeAnthropic>>;
let mcp: Awaited<ReturnType<typeof startMockMcp>>;
let n = 0;
const managers: SessionManager[] = [];

before(async () => {
  root = mkdtempSync(join(tmpdir(), 'agent-it-'));
  api = await startFakeAnthropic();
  mcp = await startMockMcp();
  process.env.ANTHROPIC_BASE_URL = api.url;
  process.env.ANTHROPIC_API_KEY = 'sk-fake';
});
after(() => {
  for (const m of managers) m.shutdown(); // otherwise the runner waits forever on the Claude processes
  api.close();
  mcp.close();
  rmSync(root, { recursive: true, force: true });
});

const server = (autoAllow: boolean, token = 'tok'): ManagedMcpServer => ({
  name: 'escanor',
  url: mcp.url,
  headers: { Authorization: `Bearer ${token}` },
  autoAllow,
  alwaysLoad: true,
  updatedAt: '',
});

function harness() {
  const dir = join(root, `s${n++}`);
  const out: AgentToHubMessage[] = [];
  const asked: string[] = [];
  const manager = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default', configDir: join(dir, 'cfg') }], (m) => out.push(m));
  managers.push(manager);
  const seenPermissions = new Set<string>();
  const results = () => out.filter((m) => m.type === 'sdk_message' && (m.message as any)?.type === 'result').length;
  // Wait for `count` finished turns, answering any permission card with `answer`.
  async function turns(count: number, answer: 'allow' | 'deny' = 'allow') {
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline && results() < count) {
      await new Promise((r) => setTimeout(r, 200));
      for (const m of out) {
        if (m.type === 'permission_request' && !seenPermissions.has(m.requestId)) {
          seenPermissions.add(m.requestId);
          asked.push(m.toolName);
          manager.resolvePermission(m.requestId, answer);
        }
      }
    }
    assert.ok(results() >= count, `timed out waiting for turn ${count}`);
  }
  const say = (id: string, text: string, first: boolean) =>
    manager.handleUserInput({ type: 'user_input', sessionId: id, ...(first ? { tempId: id } : {}), text } as never);
  return { manager, out, asked, turns, say };
}

const init = (out: AgentToHubMessage[]) => out.find((m) => m.type === 'sdk_message' && (m.message as any)?.subtype === 'init') as any;

test('a chat started after the server was installed has the tool, connected, and can call it with no prompt', async () => {
  const h = harness();
  await h.manager.setMcpServers([server(true, 'tok-new')]);
  h.say('a', 'list my providers', true);
  await h.turns(1);

  assert.deepEqual(init(h.out).message.mcp_servers.map((s: any) => [s.name, s.status]), [['escanor', 'connected']]);
  assert.ok(init(h.out).message.tools.includes('mcp__escanor__escanor_list_providers'));
  assert.deepEqual(h.asked, [], 'no permission card');
  assert.equal(mcp.toolCalls() >= 1, true);
  assert.ok(mcp.seen.some((s) => s.rpc === 'tools/call' && s.auth === 'Bearer tok-new'), 'the call carried the Escanor token');
  assert.ok(h.out.some((m) => m.type === 'mcp_status' && m.servers[0].status === 'connected'), 'the hub is told it connected');
});

test('a chat that was ALREADY running gets the server without a restart', async () => {
  const h = harness();
  h.say('b', 'hello', true);
  await h.turns(1);
  assert.deepEqual(init(h.out).message.mcp_servers, [], 'started with nothing installed');

  await h.manager.setMcpServers([server(true)]);
  const status = h.out.filter((m) => m.type === 'mcp_status').at(-1) as any;
  assert.equal(status.servers[0].status, 'connected');
  assert.equal(status.liveSessions, 1);

  const before = mcp.toolCalls();
  h.say('b', 'list my providers', false);
  await h.turns(2);
  assert.equal(mcp.toolCalls(), before + 1, 'the running chat called the newly installed tool');
  assert.deepEqual(h.asked, []);
});

test('with auto-approve off the tool asks, and a denial stops the call', async () => {
  const h = harness();
  await h.manager.setMcpServers([server(false)]);
  const before = mcp.toolCalls();
  h.say('c', 'list my providers', true);
  await h.turns(1, 'deny');
  assert.deepEqual(h.asked, ['mcp__escanor__escanor_list_providers']);
  assert.equal(mcp.toolCalls(), before, 'denied: the MCP never saw a tools/call');
});

test('turning auto-approve off, and on again, applies to the very next call in a running chat', async () => {
  const off = harness();
  await off.manager.setMcpServers([server(true)]);
  off.say('d', 'list my providers', true);
  await off.turns(1);
  assert.deepEqual(off.asked, []);
  await off.manager.setMcpServers([server(false)]);
  off.say('d', 'again', false);
  await off.turns(2);
  assert.equal(off.asked.length, 1, 'the running chat now asks');

  const on = harness();
  await on.manager.setMcpServers([server(false)]);
  on.say('e', 'list my providers', true);
  await on.turns(1);
  assert.equal(on.asked.length, 1);
  await on.manager.setMcpServers([server(true)]);
  on.say('e', 'again', false);
  await on.turns(2);
  assert.equal(on.asked.length, 1, 'and stops asking once turned back on');
});

test('an unchanged re-push is a no-op and removal takes the tool away from a running chat', async () => {
  const h = harness();
  await h.manager.setMcpServers([server(true)]);
  h.say('f', 'hello', true);
  await h.turns(1);
  const reports = h.out.filter((m) => m.type === 'mcp_status').length;
  await h.manager.setMcpServers([{ ...server(true), updatedAt: 'later' }]);
  assert.equal(h.out.filter((m) => m.type === 'mcp_status').length, reports, 'nothing changed, nothing reported');

  await h.manager.setMcpServers([]);
  assert.deepEqual((h.out.filter((m) => m.type === 'mcp_status').at(-1) as any).servers, []);
});
