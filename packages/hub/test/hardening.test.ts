// Boots the real hub and attacks it the way the security review describes.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, test } from 'node:test';
import WebSocket from 'ws';

const LEGACY = 'legacy-agent-secret-for-tests-only';
const PASSWORD = 'password-for-tests-only-123456';
const ADMIN = 'admin-secret-for-tests-only-123456';
const json = { 'content-type': 'application/json' };
const settle = (ms = 250) => new Promise((r) => setTimeout(r, ms));
const bearer = (t: string) => ({ authorization: `Bearer ${t}`, ...json });

const dirs: string[] = [];
const procs: ChildProcess[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'hub-hard-'));
  dirs.push(d);
  return d;
};
after(() => {
  procs.forEach((p) => p.kill());
  dirs.forEach((d) => rmSync(d, { recursive: true, force: true }));
});

async function startHub(env: Record<string, string> = {}, dataDir = tmp()) {
  const port = 20000 + Math.floor(Math.random() * 9000);
  const proc = spawn(process.execPath, ['--import', 'tsx', 'src/index.ts'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: { ...process.env, PORT: String(port), HUB_AGENT_TOKEN: LEGACY, APP_PASSWORD: PASSWORD, DATA_DIR: dataDir, WEB_DIST: dataDir, ...env },
    stdio: 'ignore',
  });
  procs.push(proc);
  const url = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 80; i++) {
    try {
      await fetch(`${url}/api/vms`);
      break;
    } catch {
      await settle(200);
    }
  }
  const stop = async () => {
    proc.kill();
    await new Promise((r) => proc.once('exit', r));
  };
  return { url, port, dataDir, stop, alive: () => proc.exitCode === null && proc.signalCode === null };
}
type Hub = Awaited<ReturnType<typeof startHub>>;

const login = async (hub: Hub) => ((await (await fetch(`${hub.url}/api/login`, { method: 'POST', headers: json, body: JSON.stringify({ password: PASSWORD }) })).json()) as { token: string }).token;

function agent(hub: Hub, vmName: string, opts: { token?: string; autoPong?: boolean } = {}) {
  const inbox: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${hub.port}/agent`, { headers: { authorization: `Bearer ${opts.token ?? LEGACY}` }, autoPong: opts.autoPong ?? true });
  ws.on('message', (d) => inbox.push(JSON.parse(d.toString())));
  ws.on('error', () => {});
  const closed = new Promise<number>((res) => ws.on('close', (code) => res(code)));
  const hello = (name = vmName) => ws.send(JSON.stringify({ type: 'hello', agentVersion: '0.5.0', vmName: name, hostname: 'h', accounts: [], sessions: [] }));
  const ready = new Promise<void>((res) => ws.on('open', () => { hello(); res(); }));
  return { ws, inbox, ready, closed, hello };
}

function browser(hub: Hub, token: string) {
  const inbox: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${hub.port}/ws`, ['escanor.hub.v1', `escanor.auth.${token}`]);
  ws.on('message', (d) => inbox.push(JSON.parse(d.toString())));
  ws.on('error', () => {});
  const closed = new Promise<number>((res) => ws.on('close', (code) => res(code)));
  const ready = new Promise<boolean>((res) => { ws.on('open', () => res(true)); ws.on('unexpected-response', () => res(false)); ws.on('error', () => res(false)); });
  return { ws, inbox, ready, closed };
}

const vmsOf = async (hub: Hub, token: string) => (await (await fetch(`${hub.url}/api/vms`, { headers: bearer(token) })).json()) as { id: string; name: string; connected: boolean }[];

// ---------------------------------------------------------------- #1 frames

test('malformed agent frames cannot crash the hub, and the socket keeps working', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const a = agent(hub, 'vm-frames');
  await a.ready;
  for (const f of ['null', '42', '"x"', '[]', '{"type":"hello"}', '{"type":"sdk_message"}', '{"type":"permission_request","sessionId":"s"}', '{"type":"mcp_status","servers":5,"liveSessions":1}', '{"type":"nope"}']) a.ws.send(f);
  await settle(400);
  assert.equal(hub.alive(), true, 'hub process must survive');
  assert.deepEqual((await vmsOf(hub, token)).map((v) => [v.name, v.connected]), [['vm-frames', true]]);
  a.ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 's1', message: { hi: 1 } }));
  await settle();
  assert.equal(hub.alive(), true);
  a.ws.close();
  await hub.stop();
});

test('a socket speaks for exactly one VM, and a live VM name cannot be taken over', async () => {
  const hub = await startHub();
  const a = agent(hub, 'vm-one');
  await a.ready;
  await settle();
  a.hello('vm-two'); // identity change on the same socket
  assert.equal(await a.closed, 1008);

  const first = agent(hub, 'vm-dup');
  await first.ready;
  await settle();
  const second = agent(hub, 'vm-dup');
  await second.ready;
  assert.equal(await second.closed, 1008, 'a second live agent with the same name is refused');
  assert.equal(first.ws.readyState, WebSocket.OPEN, 'the original stays connected');
  first.ws.close();
  await hub.stop();
});

test('half-open agents are dropped by the heartbeat; responsive ones stay', async () => {
  const hub = await startHub({ HUB_AGENT_PING_MS: '120' });
  const dead = agent(hub, 'vm-dead', { autoPong: false });
  const live = agent(hub, 'vm-live');
  await Promise.all([dead.ready, live.ready]);
  await Promise.race([dead.closed, settle(1500)]);
  assert.notEqual(dead.ws.readyState, WebSocket.OPEN);
  assert.equal(live.ws.readyState, WebSocket.OPEN);
  live.ws.close();
  await hub.stop();
});

test('oversized agent frames close the connection', async () => {
  const hub = await startHub({ HUB_AGENT_MAX_PAYLOAD_BYTES: '2048' });
  const a = agent(hub, 'vm-big');
  await a.ready;
  a.ws.send('x'.repeat(8192));
  assert.equal(await a.closed, 1009);
  assert.equal(hub.alive(), true);
  await hub.stop();
});

test('oversized browser frames close the connection and do not crash the hub', async () => {
  const hub = await startHub();
  const b = browser(hub, await login(hub));
  assert.equal(await b.ready, true);
  b.ws.send('x'.repeat(200_000));
  assert.equal(await b.closed, 1009);
  assert.equal(hub.alive(), true);
  await hub.stop();
});

// ---------------------------------------------------------------- #7 login

test('repeated wrong passwords lock the address out, even for the right password', async () => {
  const hub = await startHub({ HUB_LOGIN_MAX_FAILURES: '3' });
  const post = (password: unknown) => fetch(`${hub.url}/api/login`, { method: 'POST', headers: json, body: JSON.stringify({ password }) });
  for (let i = 0; i < 3; i++) assert.equal((await post('wrong')).status, 401);
  const locked = await post(PASSWORD);
  assert.equal(locked.status, 429);
  assert.ok(Number(locked.headers.get('retry-after')) > 0);
  await hub.stop();
});

test('non-string / missing passwords never yield a token', async () => {
  const hub = await startHub();
  for (const body of [{}, { password: null }, { password: ['x'] }, { password: { a: 1 } }]) {
    const r = await fetch(`${hub.url}/api/login`, { method: 'POST', headers: json, body: JSON.stringify(body) });
    assert.equal(r.status, 401);
    assert.equal(((await r.json()) as any).token, undefined);
  }
  await hub.stop();
});

test('with TRUST_PROXY the limiter keys on X-Forwarded-For, without it that header is ignored', async () => {
  const proxied = await startHub({ HUB_LOGIN_MAX_FAILURES: '2', TRUST_PROXY: '1' });
  const post = (hub: Hub, ip: string, password: string) => fetch(`${hub.url}/api/login`, { method: 'POST', headers: { ...json, 'x-forwarded-for': ip }, body: JSON.stringify({ password }) });
  await post(proxied, '203.0.113.9', 'x');
  await post(proxied, '203.0.113.9', 'x');
  assert.equal((await post(proxied, '203.0.113.9', PASSWORD)).status, 429);
  assert.equal((await post(proxied, '198.51.100.7', PASSWORD)).status, 200);
  await proxied.stop();

  const direct = await startHub({ HUB_LOGIN_MAX_FAILURES: '2' });
  await post(direct, '1.1.1.1', 'x');
  await post(direct, '2.2.2.2', 'x'); // a spoofed header must not give a fresh budget
  assert.equal((await post(direct, '3.3.3.3', PASSWORD)).status, 429);
  await direct.stop();
});

// ---------------------------------------------------------------- body limits, headers

test('big bodies are refused before authentication; unauthenticated requests never reach the large parser', async () => {
  const hub = await startHub();
  const big = JSON.stringify({ password: 'x'.repeat(200_000) });
  assert.equal((await fetch(`${hub.url}/api/login`, { method: 'POST', headers: json, body: big })).status, 413);
  assert.equal((await fetch(`${hub.url}/api/vms/v/sessions`, { method: 'POST', headers: json, body: JSON.stringify({ text: 'x'.repeat(2_000_000) }) })).status, 401);
  assert.equal((await fetch(`${hub.url}/admin/tenants`, { method: 'POST', headers: json, body: big })).status, 404, 'no admin token configured: not even parsed');
  await hub.stop();

  const withAdmin = await startHub({ HUB_ADMIN_TOKEN: ADMIN });
  assert.equal((await fetch(`${withAdmin.url}/admin/tenants`, { method: 'POST', headers: json, body: big })).status, 401, 'unauthenticated: rejected before the body is read');
  assert.equal((await fetch(`${withAdmin.url}/admin/tenants`, { method: 'POST', headers: bearer(ADMIN), body: JSON.stringify({ label: 'x'.repeat(200_000) }) })).status, 413);
  await withAdmin.stop();
});

test('responses forbid framing and restrict images (clickjacking / zero-click exfiltration)', async () => {
  const hub = await startHub();
  const r = await fetch(`${hub.url}/api/vms`);
  assert.equal(r.headers.get('x-frame-options'), 'DENY');
  const csp = r.headers.get('content-security-policy') ?? '';
  assert.match(csp, /frame-ancestors 'none'/);
  assert.match(csp, /img-src 'self' data: blob:/);
  const page = await fetch(`${hub.url}/`);
  assert.equal(page.headers.get('x-frame-options'), 'DENY');
  await hub.stop();
});

// ---------------------------------------------------------------- validation, ordering

test('request bodies are validated, and an offline VM leaves no ghost message', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const a = agent(hub, 'vm-val');
  await a.ready;
  await settle();
  const vmId = (await vmsOf(hub, token))[0].id;
  const post = (path: string, body: unknown) => fetch(`${hub.url}/api/vms/${vmId}${path}`, { method: 'POST', headers: bearer(token), body: JSON.stringify(body) });

  for (const body of [{ images: 'abc' }, { text: { a: 1 } }, { text: 'hi', cwd: 5 }, { text: 'hi', images: [{ mediaType: 'text/html', dataBase64: 'AA' }] }]) {
    assert.equal((await post('/sessions', body)).status, 400, JSON.stringify(body));
    if (!('cwd' in body)) assert.equal((await post('/sessions/s1/messages', body)).status, 400, JSON.stringify(body)); // cwd only exists on new sessions
  }
  assert.equal((await post('/sessions/s1/permission-mode', { mode: 'rm -rf /' })).status, 400);
  assert.equal((await post('/sessions/s1/effort', { effort: 'extreme' })).status, 400);
  assert.equal((await post('/sessions/s1/model', { model: { a: 1 } })).status, 400);
  assert.equal((await post('/sessions/s1/permission-response', { requestId: 'r', behavior: 'yes' })).status, 400);
  assert.equal((await post('/sessions/s1/permission-mode', { mode: 'plan' })).status, 202);

  a.ws.close();
  await a.closed;
  await settle();
  assert.equal((await post('/sessions/ghost/messages', { text: 'hello' })).status, 503);
  assert.equal((await post('/sessions', { text: 'hello' })).status, 503);
  const history = await (await fetch(`${hub.url}/api/vms/${vmId}/sessions/ghost/messages`, { headers: bearer(token) })).json();
  assert.deepEqual(history, [], 'nothing stored for an undelivered message');
  await hub.stop();
});

test('"permission resolved" is only announced when the agent actually got the answer', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const a = agent(hub, 'vm-perm');
  await a.ready;
  const b = browser(hub, token);
  await b.ready;
  await settle();
  const vmId = (await vmsOf(hub, token))[0].id;
  const respond = () => fetch(`${hub.url}/api/vms/${vmId}/sessions/s1/permission-response`, { method: 'POST', headers: bearer(token), body: JSON.stringify({ requestId: 'r1', behavior: 'allow' }) });

  assert.equal((await respond()).status, 202);
  await settle();
  assert.equal(b.inbox.filter((m) => m.type === 'permission_resolved').length, 1);

  a.ws.close();
  await a.closed;
  await settle();
  b.inbox.length = 0;
  assert.equal((await respond()).status, 503);
  await settle();
  assert.equal(b.inbox.filter((m) => m.type === 'permission_resolved').length, 0, 'the UI must not show it resolved');
  await hub.stop();
});

test('message history is capped and scoped to the VM', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const a = agent(hub, 'vm-hist');
  await a.ready;
  for (let i = 0; i < 5; i++) a.ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 'sess', message: { i } }));
  await settle(400);
  const vmId = (await vmsOf(hub, token))[0].id;
  const get = async (q = '') => (await (await fetch(`${hub.url}/api/vms/${vmId}/sessions/sess/messages${q}`, { headers: bearer(token) })).json()) as any[];
  assert.equal((await get()).length, 5);
  assert.deepEqual((await get('?limit=2')).map((m) => m.message.i), [3, 4]);
  a.ws.close();
  await hub.stop();
});

// ---------------------------------------------------------------- tokens

test('a login can mint a scoped token; a minted token cannot mint more, and an MCP token can only manage MCP', async () => {
  const hub = await startHub();
  const login1 = await login(hub);
  const mint = (auth: string, body: unknown) => fetch(`${hub.url}/api/tokens`, { method: 'POST', headers: bearer(auth), body: JSON.stringify(body) });

  const r = await mint(login1, { label: 'escanor', scope: 'mcp' });
  assert.equal(r.status, 201);
  const mcp = (await r.json()) as { token: string; scope: string; expiresAt: string };
  assert.equal(mcp.scope, 'mcp');
  assert.ok(Date.parse(mcp.expiresAt) > Date.now(), 'tokens carry an expiry');

  assert.equal((await mint(mcp.token, { label: 'forever' })).status, 403, 'an API token cannot mint another');
  const full = (await (await mint(login1, { label: 'ci' })).json()) as { token: string };
  assert.equal((await mint(full.token, { label: 'forever' })).status, 403, 'not even a full-scope one');
  assert.equal((await mint(login1, { label: 'x', scope: 'admin' })).status, 400);
  assert.equal((await mint(login1, { label: 'x', ttlSeconds: 5 })).status, 400);

  const asMcp = (path: string, init: RequestInit = {}) => fetch(`${hub.url}/api${path}`, { ...init, headers: bearer(mcp.token) });
  assert.equal((await asMcp('/mcp-servers')).status, 200);
  assert.equal((await asMcp('/mcp-servers/escanor', { method: 'PUT', body: JSON.stringify({ url: 'https://mcp.example/' }) })).status, 200);
  assert.equal((await asMcp('/vms')).status, 403);
  assert.equal((await asMcp('/tokens')).status, 403);
  assert.equal((await asMcp('/vms/x/sessions', { method: 'POST', body: JSON.stringify({ text: 'run it' }) })).status, 403);
  assert.equal((await asMcp('/vms/x/sessions/y/permission-mode', { method: 'POST', body: JSON.stringify({ mode: 'bypassPermissions' }) })).status, 403);

  const ws = browser(hub, mcp.token);
  assert.equal(await ws.ready, false, 'an MCP token must not stream every transcript');
  await hub.stop();
});

test('a revoked browser session is disconnected', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const b = browser(hub, token);
  await b.ready;
  await fetch(`${hub.url}/api/logout`, { method: 'POST', headers: bearer(token) });
  assert.equal(await b.closed, 1008);
  await hub.stop();
});

test('the ?token= websocket fallback is off unless the operator re-enables it', async () => {
  const off = await startHub();
  const token = await login(off);
  const viaQuery = (hub: Hub) => new Promise<boolean>((res) => {
    const ws = new WebSocket(`ws://127.0.0.1:${hub.port}/ws?token=${token}`);
    ws.on('open', () => { ws.close(); res(true); });
    ws.on('error', () => res(false));
    ws.on('unexpected-response', () => res(false));
  });
  assert.equal(await viaQuery(off), false);
  assert.equal(await (browser(off, token)).ready, true, 'the subprotocol credential still works');
  await off.stop();
});

// ---------------------------------------------------------------- MCP registry

test('updating only the URL keeps headers and approval flags; a string "false" is rejected; SSRF targets are refused', async () => {
  const hub = await startHub();
  const token = await login(hub);
  const put = (name: string, body: unknown) => fetch(`${hub.url}/api/mcp-servers/${name}`, { method: 'PUT', headers: bearer(token), body: JSON.stringify(body) });
  const overview = async () => ((await (await fetch(`${hub.url}/api/mcp-servers`, { headers: bearer(token) })).json()) as any).servers as any[];

  assert.equal((await put('escanor', { url: 'https://old.example/', headers: { Authorization: 'Bearer keep-me' }, autoAllow: false, autoAllowReads: true })).status, 200);
  assert.equal((await put('escanor', { url: 'https://new.example/' })).status, 200);
  const [s] = await overview();
  assert.equal(s.url, 'https://new.example/');
  assert.deepEqual(s.headerNames, ['Authorization']);
  assert.equal(s.autoAllow, false);
  assert.equal(s.autoAllowReads, true);

  assert.equal((await put('other', { url: 'https://x.example/', autoAllow: 'false' })).status, 400);
  assert.equal((await put('a__b', { url: 'https://x.example/' })).status, 400);
  for (const url of ['http://169.254.169.254/latest', 'http://localhost:9/', 'http://10.0.0.1/', 'http://[::1]/']) {
    assert.equal((await put('ssrf', { url })).status, 400, url);
  }
  assert.equal((await overview()).some((x) => x.name === 'ssrf'), false);
  await hub.stop();
});

test('private MCP URLs need the operator opt-in; metadata addresses never pass', async () => {
  const hub = await startHub({ HUB_MCP_ALLOW_PRIVATE: '1' });
  const token = await login(hub);
  const put = (url: string) => fetch(`${hub.url}/api/mcp-servers/s`, { method: 'PUT', headers: bearer(token), body: JSON.stringify({ url }) });
  assert.equal((await put('http://127.0.0.1:8787/mcp')).status, 200);
  assert.equal((await put('http://169.254.169.254/')).status, 400);
  await hub.stop();
});

// ---------------------------------------------------------------- secrets on disk

test('credentials are encrypted and redacted in the database file, which is owner-only', async () => {
  const dataDir = tmp();
  const hub = await startHub({}, dataDir);
  const token = await login(hub);
  await fetch(`${hub.url}/api/mcp-servers/escanor`, { method: 'PUT', headers: bearer(token), body: JSON.stringify({ url: 'https://mcp.example/', headers: { Authorization: 'Bearer on-disk-header-secret' } }) });
  const a = agent(hub, 'vm-disk');
  await a.ready;
  a.ws.send(JSON.stringify({ type: 'sdk_message', sessionId: 's', message: { text: 'curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345" x' } }));
  await settle(400);
  a.ws.close();
  await hub.stop();

  const raw = new DatabaseSync(join(dataDir, 'hub.sqlite'));
  const mcp = (raw.prepare('SELECT config_json FROM mcp_servers').get() as { config_json: string }).config_json;
  assert.equal(mcp.includes('on-disk-header-secret'), false);
  const msgs = (raw.prepare('SELECT payload FROM messages').all() as { payload: string }[]).map((r) => r.payload).join('\n');
  assert.equal(msgs.includes('abcdefghijklmnopqrstuvwxyz012345'), false);
  assert.equal(statSync(join(dataDir, 'hub.sqlite')).mode & 0o077, 0);
});

test('placeholder or weak secrets stop the hub from starting', async () => {
  for (const env of [{ APP_PASSWORD: 'change-me' }, { HUB_AGENT_TOKEN: 'change-me-change-me-change-me' }, { HUB_ADMIN_TOKEN: 'admin-secret' }]) {
    const port = 29000 + Math.floor(Math.random() * 900);
    const proc = spawn(process.execPath, ['--import', 'tsx', 'src/index.ts'], {
      cwd: new URL('..', import.meta.url).pathname,
      env: { ...process.env, PORT: String(port), HUB_AGENT_TOKEN: LEGACY, APP_PASSWORD: PASSWORD, DATA_DIR: tmp(), ...env },
      stdio: 'ignore',
    });
    procs.push(proc);
    const code = await Promise.race([new Promise<number | null>((r) => proc.once('exit', r)), settle(8000).then(() => 'still-running' as const)]);
    assert.notEqual(code, 'still-running', `${JSON.stringify(env)} must be refused`);
  }
});
