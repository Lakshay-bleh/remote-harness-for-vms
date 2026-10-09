/**
 * The REAL Escanor Desktop remote stack (escanor-desktop/packages/remote/src: gateway, pairing, approval pairing, handler, cloud
 * relay link, and its fake backend), started for interop_test.dart. Nothing of the desktop is copied or changed: it is imported by
 * absolute path, read-only. `ws` is resolved from wherever WS_PATH says (the desktop checkout may not have its packages installed).
 *
 * Prints one JSON line {gateway, api} once ready, then serves:
 *   the phone's backend API, as mongo-backend has it:  POST /agents/commands, GET /agents/commands/:id, GET /agents
 *   test controls:                                     POST /test/offer, GET /test/state, POST /test/approval, POST /test/close-gateway
 */
import http from 'node:http';
import { register } from 'node:module';
import { pathToFileURL } from 'node:url';

const DESKTOP = process.env.DESKTOP ?? '/home/lakshay/Desktop/StartUp/escanor-desktop';
const WS_PATH = process.env.WS_PATH ?? new URL('./node_modules/ws', import.meta.url).pathname;
const wsUrl = pathToFileURL(`${WS_PATH}/wrapper.mjs`).href;
register(
  'data:text/javascript,' +
    encodeURIComponent(`export async function resolve(s, c, n) { return s === 'ws' ? { url: ${JSON.stringify(wsUrl)}, shortCircuit: true } : n(s, c); }`),
);

const src = `${DESKTOP}/packages/remote/src`;
const { DeviceStore } = await import(`${src}/devices.ts`);
const { PairingManager } = await import(`${src}/pairing.ts`);
const { LanApproval } = await import(`${src}/lan-approval.ts`);
const { RemoteHandler } = await import(`${src}/handler.ts`);
const { startGateway } = await import(`${src}/gateway.ts`);
const { MachineLink } = await import(`${src}/relay.ts`);
const { fakeBackend } = await import(`${src}/testing/fake-backend.ts`);
const { AccountClient } = await import(`${DESKTOP}/packages/account/src/client.ts`);

const MACHINE = { name: 'Interop Laptop', hostname: 'box', os: 'linux', appVersion: '9.9.9' };
const store = new DeviceStore({ load: () => null, save: () => {} });
const pairing = new PairingManager({ store });
const confirms: string[] = [];
const lanApproval = new LanApproval({ store, ask: async (info: { confirm: string }) => (confirms.push(info.confirm), true) });
const approvalListeners = new Set<(a: unknown) => void>();
const answered: Array<[string, boolean]> = [];
const backend = {
  machine: () => MACHINE,
  capabilities: () => [{ id: 'system.stats', group: 'system', describe: 'Stats', risk: 'read', inputSchema: { type: 'object' } }],
  call: async (_d: unknown, capability: string, input: unknown) => ({ ok: true, result: { capability, input, cpu: 4 } }),
  chat: async (_d: unknown, text: string, fresh?: boolean) => ({ reply: `heard: ${text}${fresh ? ' (fresh)' : ''}`, listenAgain: false }),
  stats: async () => ({ cpu: 4 }),
  pendingApprovals: () => [{ approvalId: 'p1', capabilityId: 'docker.rm', describe: 'Delete', risk: 'destructive', input: {} }],
  respondApproval: (id: string, ok: boolean) => (answered.push([id, ok]), true),
  groups: () => [{ id: 'os', label: 'Open apps and websites', about: 'Open apps', enabled: false }],
  requestGroup: () => 'asked',
  activity: ({ limit }: { limit: number }) => ({ items: [{ at: '2026-10-04T10:00:00Z', capabilityId: 'os.open_url', caller: 'voice', risk: 'read', outcome: 'ok', ms: 3 }].slice(0, limit), more: false }),
};
const handler = new RemoteHandler(backend);
const feed = {
  onEvent: () => () => {},
  onApproval: (cb: (a: unknown) => void) => (approvalListeners.add(cb), () => approvalListeners.delete(cb)),
  onApprovalResolved: () => () => {},
  pendingApprovals: () => [],
  stats: async () => ({ cpu: 4 }),
};
let gateway = await startGateway({ store, pairing, lanApproval, handler, feed, machine: () => MACHINE, host: '127.0.0.1' });

const fb = await fakeBackend();
let tokens: { access: string; refresh: string } | null = { access: 'USER', refresh: 'R' };
const account = new AccountClient({ apiBase: fb.base, store: { load: () => tokens, save: (t: typeof tokens) => void (tokens = t), clear: () => void (tokens = null) } });
let creds: unknown = null;
const link = new MachineLink({
  account,
  store: { load: () => creds, save: (c: unknown) => void (creds = c), clear: () => void (creds = null) },
  devices: store,
  handler,
  pairing,
  machine: () => ({ ...MACHINE, architecture: 'x64' }),
  snapshot: async () => ({ capabilities: {}, snapshots: {}, health: { app: 'escanor-desktop' } }),
  heartbeatMs: 200,
  activePollMs: 20,
  idlePollMs: 20,
});
link.start();
for (let i = 0; i < 200 && !link.status().agentId; i++) await new Promise((r) => setTimeout(r, 20));

const api = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', async () => {
    const send = (status: number, b: unknown) => (res.writeHead(status, { 'Content-Type': 'application/json' }), res.end(JSON.stringify(b)));
    const body = raw ? JSON.parse(raw) : {};
    const path = (req.url ?? '').split('?')[0];
    try {
      if (req.method === 'GET' && path === '/agents') {
        return send(200, { agents: [{ id: link.status().agentId, name: MACHINE.name, runtime_status: 'online', last_heartbeat_at: new Date().toISOString(), health: { app: 'escanor-desktop' } }, { id: 'web-only', name: 'A server', runtime_status: 'online', health: {} }] });
      }
      if (req.method === 'POST' && path === '/agents/commands') {
        if (body.agent_id !== link.status().agentId) return send(404, { detail: 'Machine not found' });
        const id = fb.queue(body.plugin, body.action, body.parameters);
        return send(200, { id, status: 'queued' });
      }
      const m = /^\/agents\/commands\/([^/]+)$/.exec(path);
      if (req.method === 'GET' && m) {
        const c = fb.state.queue.find((x: { id: string }) => x.id === decodeURIComponent(m[1]));
        return c ? send(200, { id: c.id, status: c.status, result: c.result ?? null, error: c.error ?? null }) : send(404, { detail: 'not found' });
      }
      if (req.method === 'POST' && path === '/test/offer') {
        const offer = pairing.create();
        link.nudge();
        return send(200, { code: offer.code, agentId: link.status().agentId, lan: `127.0.0.1:${gateway.port}` });
      }
      if (req.method === 'GET' && path === '/test/state') {
        return send(200, { devices: store.list().map((d: { id: string; name: string }) => ({ id: d.id, name: d.name, key: store.get(d.id).key })), confirms, answered, cloudText: JSON.stringify(fb.state.queue) });
      }
      if (req.method === 'POST' && path === '/test/approval') {
        approvalListeners.forEach((cb) => cb(body));
        return send(200, { ok: true });
      }
      if (req.method === 'POST' && path === '/test/close-gateway') {
        await gateway.close();
        return send(200, { ok: true });
      }
      if (req.method === 'POST' && path === '/test/reopen-gateway') {
        gateway = await startGateway({ store, pairing, lanApproval, handler, feed, machine: () => MACHINE, host: '127.0.0.1' });
        return send(200, { lan: `127.0.0.1:${gateway.port}` });
      }
      send(404, { detail: 'not found' });
    } catch (e) {
      send(500, { detail: String(e) });
    }
  });
});
await new Promise<void>((r) => api.listen(0, '127.0.0.1', () => r()));
process.stdout.write(JSON.stringify({ gateway: `127.0.0.1:${gateway.port}`, api: `http://127.0.0.1:${(api.address() as { port: number }).port}`, agentId: link.status().agentId }) + '\n');

// Ends with the test run: stdin closing is the signal.
process.stdin.resume();
process.stdin.on('end', () => process.exit(0));
