import assert from 'node:assert/strict';
import test from 'node:test';
import { agentSupportsMcp, isReadOnlyMcpCall, parseMcpServerInput, toMcpServerDto } from '../src/protocol.ts';

const ok = (name: string, body: unknown) => {
  const r = parseMcpServerInput(name, body);
  assert.ok(r.ok, r.ok ? '' : r.error);
  return r.server;
};
const bad = (name: string, body: unknown) => {
  const r = parseMcpServerInput(name, body);
  assert.equal(r.ok, false, `expected ${JSON.stringify(body)} to be rejected`);
  return r.ok ? '' : r.error;
};

test('a server is accepted with sensible defaults', () => {
  const s = ok('escanor', { url: 'https://mcp.escanor.in/' });
  // Approving every tool of a server is something the caller asks for; a new server starts out asking.
  assert.equal(s.autoAllow, false);
  assert.equal(s.alwaysLoad, true);
  assert.equal(s.url, 'https://mcp.escanor.in/');
});

test('flags can be turned off explicitly', () => {
  const s = ok('escanor', { url: 'https://x.example/', autoAllow: false, alwaysLoad: false });
  assert.equal(s.autoAllow, false);
  assert.equal(s.alwaysLoad, false);
});

test('names must survive as a Claude Code tool namespace', () => {
  for (const name of ['', 'Escanor', 'has space', '-lead', 'a'.repeat(33), 'dots.not.ok', '../x']) bad(name, { url: 'https://x/' });
  for (const name of ['escanor', 'a', 'my_server-2', '0abc']) ok(name, { url: 'https://x/' });
});

test('only http(s) URLs without embedded credentials', () => {
  bad('s', {});
  bad('s', { url: 42 });
  bad('s', { url: 'not a url' });
  bad('s', { url: 'ftp://x/' });
  bad('s', { url: 'file:///etc/passwd' });
  bad('s', { url: 'https://user:pw@x.example/' });
  bad('s', { url: 'http://127.0.0.1:8787/mcp' }); // loopback / private networks only when the operator opts in
  assert.ok(parseMcpServerInput('s', { url: 'http://127.0.0.1:8787/mcp' }, { allowPrivate: true }).ok);
});

test('headers cannot smuggle extra headers', () => {
  bad('s', { url: 'https://x/', headers: { 'X-A': 'v\r\nEvil: 1' } });
  bad('s', { url: 'https://x/', headers: { 'X-A': 'v\nEvil: 1' } });
  bad('s', { url: 'https://x/', headers: { 'bad name': 'v' } });
  bad('s', { url: 'https://x/', headers: { A: 1 } });
  bad('s', { url: 'https://x/', headers: ['x'] });
  bad('s', { url: 'https://x/', headers: Object.fromEntries(Array.from({ length: 17 }, (_, i) => [`H${i}`, 'v'])) });
  assert.deepEqual(ok('s', { url: 'https://x/', headers: { Authorization: 'Bearer t' } }).headers, { Authorization: 'Bearer t' });
});

test('the DTO never carries header values', () => {
  const dto = toMcpServerDto({ name: 'escanor', url: 'https://x/', headers: { Authorization: 'Bearer secret' }, updatedAt: 't' });
  assert.deepEqual(dto.headerNames, ['Authorization']);
  assert.ok(!JSON.stringify(dto).includes('secret'));
});

test('agents before 0.3.0 are reported as unable to install MCP servers', () => {
  for (const v of ['0.2.0', '0.2.9', '0.1.0', '', null, undefined, 'garbage']) assert.equal(agentSupportsMcp(v as never), false, String(v));
  for (const v of ['0.3.0', '0.3.1', '0.10.0', '1.0.0', '1']) assert.equal(agentSupportsMcp(v), true, v);
});

const invoke = (tool_id: unknown, args?: unknown) => isReadOnlyMcpCall('escanor_invoke', { tool_id, arguments: args } as never);

test('Escanor discovery tools are read-only', () => {
  for (const t of ['escanor_list_providers', 'escanor_connection_status', 'escanor_list_tools', 'escanor_usage_stats']) assert.equal(isReadOnlyMcpCall(t, {}), true, t);
});

test('an invoke that only reads is read-only', () => {
  for (const id of ['github.list_repos', 'vercel_list_deployments', 'aws_ec2_describe_instances', 'gcp.compute.instances.get', 'stripe.balance.retrieve', 'sentry_search_issues', 'GitHub.List_Repos']) {
    assert.equal(invoke(id), true, id);
  }
});

test('anything that changes something is not', () => {
  for (const id of ['github.create_repo', 'vercel_delete_deployment', 'aws_ec2_terminate_instances', 'github.merge_pull_request', 'stripe.refund.create', 'kubernetes_apply', 'cloudflare_purge_cache', 'gcp.compute.instances.stop']) {
    assert.equal(invoke(id), false, id);
  }
});

test('mixed or sensitive calls ask, even though they contain a read verb', () => {
  for (const id of ['github.get_or_create_repo', 'list_and_delete', 'aws_secretsmanager_get_secret_value', 'cloudflare_user_tokens_list', 'github.list_deploy_keys', 'supabase_get_api_keys', 'vault.read']) {
    assert.equal(invoke(id), false, id);
  }
});

test('unrecognised or malformed calls ask (fail closed)', () => {
  for (const id of ['', undefined, null, 42, 'mystery', 'x.y.z', '___']) assert.equal(invoke(id), false, String(id));
  assert.equal(isReadOnlyMcpCall('escanor_invoke', undefined), false);
  assert.equal(isReadOnlyMcpCall('some_other_tool', { tool_id: 'github.list_repos' }), false);
  assert.equal(isReadOnlyMcpCall('escanor_list_providers_and_more', {}), false);
});

test('an explicit confirm flag means it was destructive, whatever the name says', () => {
  assert.equal(invoke('github.list_repos', { confirm: true }), false);
  assert.equal(invoke('github.list_repos', { org: 'x' }), true);
});

test('autoAllowReads defaults off and is parsed', () => {
  assert.equal(ok('s', { url: 'https://x/' }).autoAllowReads, false);
  assert.equal(ok('s', { url: 'https://x/', autoAllow: false, autoAllowReads: true }).autoAllowReads, true);
});
