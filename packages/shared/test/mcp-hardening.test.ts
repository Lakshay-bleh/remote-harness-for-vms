import assert from 'node:assert/strict';
import test from 'node:test';
import { isReadOnlyMcpCall, parseMcpServerInput, isValidMcpServerName } from '../src/protocol.ts';
import { parseAgentFrame } from '../src/validate.ts';

const parse = (name: string, body: unknown, opts?: Parameters<typeof parseMcpServerInput>[2]) => parseMcpServerInput(name, body, opts);

// ---- #5: server names ----

test('server names cannot contain "__" (it is the separator in mcp__<server>__<tool>)', () => {
  for (const n of ['a__b', 'a__', 'x__y__z', 'a_']) {
    assert.equal(isValidMcpServerName(n), false, n);
    assert.equal(parse(n, { url: 'https://x.example/' }).ok, false, n);
  }
  for (const n of ['a', 'a_b', 'a-b', 'my_server-2']) assert.equal(isValidMcpServerName(n), true, n);
});

// ---- #5: booleans are booleans ----

test('the string "false" is not a boolean: flags must be real booleans', () => {
  for (const flag of ['autoAllow', 'autoAllowReads', 'alwaysLoad']) {
    for (const bad of ['false', 'true', 0, 1, 'no', null, {}, []]) {
      const r = parse('s', { url: 'https://x.example/', [flag]: bad });
      assert.equal(r.ok, false, `${flag}=${JSON.stringify(bad)} must be rejected`);
    }
    assert.equal(parse('s', { url: 'https://x.example/', [flag]: false }).ok, true);
    assert.equal(parse('s', { url: 'https://x.example/', [flag]: true }).ok, true);
  }
});

// ---- #5: blanket approval is opt-in, and an update does not silently reset it ----

test('a new server is not blanket-approved unless it says so', () => {
  const r = parse('s', { url: 'https://x.example/' });
  assert.ok(r.ok);
  assert.equal(r.server.autoAllow, false);
});

test('updating only the URL keeps the existing flags and headers', () => {
  const existing = {
    name: 's', url: 'https://old.example/', headers: { Authorization: 'Bearer keep-me' },
    autoAllow: false, autoAllowReads: true, alwaysLoad: false, managedBy: 'escanor', updatedAt: 't',
  };
  const r = parse('s', { url: 'https://new.example/' }, { existing });
  assert.ok(r.ok);
  assert.equal(r.server.url, 'https://new.example/');
  assert.deepEqual(r.server.headers, { Authorization: 'Bearer keep-me' });
  assert.equal(r.server.autoAllow, false);
  assert.equal(r.server.autoAllowReads, true);
  assert.equal(r.server.alwaysLoad, false);
  assert.equal(r.server.managedBy, 'escanor');
});

test('an update can still change a flag or clear headers explicitly', () => {
  const existing = { name: 's', url: 'https://x.example/', headers: { A: 'b' }, autoAllow: true, updatedAt: 't' };
  const r = parse('s', { url: 'https://x.example/', autoAllow: false, headers: {} }, { existing });
  assert.ok(r.ok);
  assert.equal(r.server.autoAllow, false);
  assert.deepEqual(r.server.headers, {});
});

// ---- #5: SSRF ----

test('metadata and link-local targets are always refused; private ones only when allowed', () => {
  for (const url of ['http://169.254.169.254/', 'http://[fd00:ec2::254]/', 'http://metadata.google.internal/']) {
    assert.equal(parse('s', { url }, { allowPrivate: true }).ok, false, url);
  }
  for (const url of ['http://localhost:8787/mcp', 'http://127.0.0.1/', 'http://10.1.2.3/', 'http://192.168.0.5/']) {
    assert.equal(parse('s', { url }).ok, false, `${url} refused by default`);
    assert.equal(parse('s', { url }, { allowPrivate: true }).ok, true, `${url} allowed when opted in`);
  }
  assert.equal(parse('s', { url: 'https://mcp.example.com/mcp' }).ok, true);
});

// ---- #6: read-only classifier fails closed ----

const invoke = (tool_id: unknown, args?: unknown) => isReadOnlyMcpCall('escanor_invoke', { tool_id, arguments: args } as never);

test('compound operations that hide a change behind a read verb are not read-only', () => {
  for (const id of ['list_and_drop_tables', 'get_and_notify', 'list_then_wipe', 'fetch_and_install', 'github.list_and_fork', 'describe_then_reboot']) {
    assert.equal(invoke(id), false, id);
  }
});

test('more change verbs are recognised', () => {
  for (const id of ['db.drop_table', 'slack.notify_channel', 'disk.wipe', 'pkg.install', 'pkg.uninstall', 'mail.email_user', 'x.erase', 'x.truncate', 'ec2.shutdown', 'sms.text_user']) {
    assert.equal(invoke(id), false, id);
  }
});

test('nouns that happen to be verbs do not make a plain read ask', () => {
  for (const id of ['sentry.get_issue_logs', 'github.list_issues', 'github.get_issue', 'notion.get_page', 'slack.get_message', 'github.list_comments', 'sentry.get_alert', 'github.get_email', 'vercel_list_deployments']) {
    assert.equal(invoke(id), true, id);
  }
});

test('the operation must be led by a read verb', () => {
  assert.equal(invoke('github.list_repos'), true);
  assert.equal(invoke('stripe.balance.retrieve'), true);
  for (const id of ['mystery_operation', 'github.repos', 'x.y.z']) assert.equal(invoke(id), false, id);
});

test('arguments are inspected: a query tool carrying a write is not a read', () => {
  assert.equal(invoke('database_query', { sql: 'SELECT id, name FROM users WHERE active' }), true);
  assert.equal(invoke('postgres.query', { query: 'select count(*) from updates' }), true);
  for (const sql of ['DELETE FROM users', 'delete from users where 1=1', 'DROP TABLE users', 'UPDATE users SET admin = true', 'INSERT INTO t VALUES (1)', 'TRUNCATE users', 'ALTER TABLE t ADD c int', 'GRANT ALL ON t TO x', 'SELECT 1; DROP TABLE t']) {
    assert.equal(invoke('database_query', { sql }), false, sql);
  }
});

test('a GraphQL mutation is not a read, wherever it is nested', () => {
  assert.equal(invoke('github.graphql_query', { query: '{ viewer { login } }' }), true);
  assert.equal(invoke('github.graphql_query', { query: 'mutation { deleteRepo(id: 1) { ok } }' }), false);
  assert.equal(invoke('github.graphql_query', { nested: { deeper: [{ query: 'mutation Foo { x }' }] } }), false);
});

test('existing behaviour is preserved', () => {
  assert.equal(invoke('github.get_or_create_repo'), false);
  assert.equal(invoke('github.list_repos', { confirm: true }), false);
  assert.equal(isReadOnlyMcpCall('escanor_list_providers', {}), true);
});

// ---- #1: the validator knows every frame the agent really sends ----

test('mcp_status frames are accepted, malformed ones are not', () => {
  const ok = { type: 'mcp_status', servers: [{ name: 'escanor', status: 'connected' }], liveSessions: 2 };
  assert.deepEqual(parseAgentFrame(JSON.stringify(ok)), ok);
  for (const bad of [{ type: 'mcp_status' }, { type: 'mcp_status', servers: 'x', liveSessions: 1 }, { type: 'mcp_status', servers: [{ name: 1, status: 'connected' }], liveSessions: 1 }, { type: 'mcp_status', servers: [], liveSessions: 'many' }]) {
    assert.equal(parseAgentFrame(JSON.stringify(bad)), null, JSON.stringify(bad));
  }
});
