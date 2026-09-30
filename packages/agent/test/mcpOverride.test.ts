// A machine sent to look at one incident uses the incident's own MCP token, not the workspace's standing one.
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import type { ManagedMcpServer } from '@remote-harness/shared';

// config.ts insists on these at import; the tests never connect anywhere.
process.env.HUB_URL ||= 'ws://127.0.0.1:1/agent';
process.env.HUB_TOKEN ||= 'test';
const { parseMcpOverride } = await import('../src/config.ts');
const { SessionManager } = await import('../src/sessionManager.ts');
type SessionManager = InstanceType<typeof SessionManager>;

const hubEntry = (over: Partial<ManagedMcpServer> = {}): ManagedMcpServer => ({
  name: 'escanor',
  url: 'https://mcp.example/',
  headers: { Authorization: 'Bearer workspace-standing-token' },
  autoAllow: true, // the workspace's standing entry approves everything
  updatedAt: 'now',
  ...over,
});

const manager = (override: ReturnType<typeof parseMcpOverride>): SessionManager =>
  new SessionManager('/tmp/work', mkdtempSync(join(tmpdir(), 'agent-')), [{ id: 'default', label: 'default', configDir: '/tmp/x' } as never], () => undefined, { mcpOverride: override });

const state = (m: SessionManager) => m as unknown as { sdkMcpConfig(): Record<string, { url: string; headers?: Record<string, string> }>; isAutoAllowedMcpTool(t: string, i: Record<string, unknown>): boolean };

test('the override is read strictly and fails closed', () => {
  const o = parseMcpOverride(JSON.stringify({ name: 'escanor', url: 'https://mcp.example/', token: 'incident-token' }));
  assert.deepEqual(o, {
    name: 'escanor',
    url: 'https://mcp.example/',
    headers: { Authorization: 'Bearer incident-token' },
    autoAllow: false,
    autoAllowReads: true,
    alwaysLoad: true,
    managedBy: 'override',
  });
  assert.equal(parseMcpOverride(JSON.stringify({ name: 'escanor', url: 'https://mcp.example/', token: 't', autoAllow: true }))?.autoAllow, true, 'only when it says so explicitly');
  for (const bad of [undefined, '', 'not json', '{}', JSON.stringify({ name: 'Bad Name', url: 'https://x', token: 't' }), JSON.stringify({ name: 'x', url: 'file:///etc/passwd', token: 't' }), JSON.stringify({ name: 'x', url: 'https://x' })]) {
    assert.equal(parseMcpOverride(bad as string | undefined), null, String(bad));
  }
});

test('the incident token replaces the hub entry of the same name, and nothing that changes a service is pre-approved', async () => {
  const m = manager(parseMcpOverride(JSON.stringify({ name: 'escanor', url: 'https://mcp.example/', token: 'incident-token' })));
  await m.setMcpServers([hubEntry(), hubEntry({ name: 'other', url: 'https://other.example/', headers: { Authorization: 'Bearer o' } })]);
  const cfg = state(m).sdkMcpConfig();
  assert.equal(cfg.escanor!.headers!.Authorization, 'Bearer incident-token');
  assert.ok(!JSON.stringify(cfg).includes('workspace-standing-token'));
  assert.equal(cfg.other!.headers!.Authorization, 'Bearer o', 'other servers are untouched');

  const allowed = (tool: string, input: Record<string, unknown> = {}) => state(m).isAutoAllowedMcpTool(tool, input);
  assert.equal(allowed('mcp__escanor__escanor_connection_status'), true, 'looking is free');
  assert.equal(allowed('mcp__escanor__escanor_invoke', { tool_id: 'stripe.list_charges', arguments: {} }), true);
  assert.equal(allowed('mcp__escanor__escanor_invoke', { tool_id: 'stripe.refund_charge', arguments: {} }), false, 'changing something waits for a person');
  assert.equal(allowed('mcp__escanor__escanor_invoke', { tool_id: 'github.delete_repo', arguments: {} }), false);
});

test('the override is there before the hub has said anything, and a hub push that leaves it out cannot remove it', async () => {
  const m = manager(parseMcpOverride(JSON.stringify({ name: 'escanor', url: 'https://mcp.example/', token: 'incident-token' })));
  assert.equal(state(m).sdkMcpConfig().escanor!.headers!.Authorization, 'Bearer incident-token');
  await m.setMcpServers([]);
  assert.equal(state(m).sdkMcpConfig().escanor!.headers!.Authorization, 'Bearer incident-token');
});

test('without an override the hub decides, as before', async () => {
  const m = manager(null);
  await m.setMcpServers([hubEntry()]);
  assert.equal(state(m).sdkMcpConfig().escanor!.headers!.Authorization, 'Bearer workspace-standing-token');
  assert.equal(state(m).isAutoAllowedMcpTool('mcp__escanor__escanor_invoke', { tool_id: 'stripe.refund_charge' }), true);
});
