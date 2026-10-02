import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { HubToBrowserMessage } from '@remote-harness/shared';
import type { Db, MachineScope } from './db.js';

export type BrowserServerOptions = {
  // The /ws?token= form puts the credential in the URL, which proxies and CDNs log. Only for old clients, and off by default.
  allowQueryToken?: boolean;
};

export function createBrowserServer(db: Db, opts: BrowserServerOptions = {}) {
  const wss = new WebSocketServer({
    noServer: true,
    // A browser only ever sends a 4-byte "ping"; anything large is abuse.
    maxPayload: 16 * 1024,
    handleProtocols: p => p.has('escanor.hub.v1') ? 'escanor.hub.v1' : false,
  });
  function requestToken(req: IncomingMessage): string {
    const value = (req.headers['sec-websocket-protocol'] ?? '').split(',').map(v => v.trim()).find(v => v.startsWith('escanor.auth.'));
    if (value) return value.slice('escanor.auth.'.length);
    return opts.allowQueryToken ? new URL(req.url ?? '', 'http://localhost').searchParams.get('token') ?? '' : '';
  }
  const credentials = new WeakMap<WebSocket, string>();
  // A token limited to MCP management has no business receiving every transcript the hub broadcasts.
  const streamable = (token: string) => {
    const c = db.credentialForApiToken(token);
    return c !== null && c.scope === 'full';
  };
  const valid = (ws: WebSocket) => streamable(credentials.get(ws) ?? '') || Boolean(db.machineForApiToken(credentials.get(ws) ?? ''));

  function authorizeScoped(req: IncomingMessage): { tenantId: string; machine?: MachineScope } | null {
    const token = requestToken(req);
    const cred = db.credentialForApiToken(token);
    if (cred) return cred.scope === 'full' ? { tenantId: cred.tenantId } : null;
    const machine = db.machineForApiToken(token);
    return machine ? { tenantId: machine.tenantId, machine } : null;
  }
  const authorize = (req: IncomingMessage): string | null => authorizeScoped(req)?.tenantId ?? null;

  // A browser only ever hears about its own tenant; a machine-scoped token only about its own machine.
  const clients = new Map<WebSocket, { tenantId: string; machine?: MachineScope }>();
  wss.on('connection', (ws, req) => {
    const auth = authorizeScoped(req);
    if (!auth) {
      ws.close(1008, 'unauthorized');
      return;
    }
    credentials.set(ws, requestToken(req));
    clients.set(ws, auth);
    ws.on('error', (err) => console.error('[browser] socket error:', err.message));
    if (auth.machine) {
      const timer = setTimeout(() => ws.close(1008, 'credential expired'), Math.max(0, Date.parse(auth.machine.expiresAt) - Date.now()));
      ws.on('close', () => clearTimeout(timer));
    }
    ws.on('close', () => clients.delete(ws));
  });

  return {
    wss,
    authorize,
    closeRevokedSessions(): void {
      for (const ws of clients.keys()) if (!valid(ws)) ws.close(1008, 'Session expired or revoked');
    },
    broadcast(tenantId: string, msg: HubToBrowserMessage): void {
      const payload = JSON.stringify(msg);
      const vmId = 'vmId' in msg ? (msg as { vmId?: string }).vmId : undefined;
      // The name of the machine the message is about, looked up once, for the clients limited to a machine.
      const vmName = vmId ? db.for(tenantId).listVms().find((v) => v.id === vmId)?.name : undefined;
      for (const [ws, c] of clients) {
        if (!valid(ws)) { ws.close(1008, 'Session expired or revoked'); continue; }
        if (c.tenantId !== tenantId || ws.readyState !== WebSocket.OPEN) continue;
        if (c.machine && (!vmName || vmName !== c.machine.vmName)) continue;
        ws.send(payload);
      }
    },
    disconnectTenant(tenantId: string): void {
      for (const [ws, c] of clients) if (c.tenantId === tenantId) ws.close(1008, 'tenant removed');
    },
    disconnectMachine(tenantId: string, vmName: string): void {
      for (const [ws, c] of clients) if (c.tenantId === tenantId && c.machine?.vmName === vmName) ws.close(1008, 'credential revoked');
    },
  };
}

export type BrowserServer = ReturnType<typeof createBrowserServer>;
