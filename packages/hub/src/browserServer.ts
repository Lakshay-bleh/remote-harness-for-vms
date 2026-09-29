import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { HubToBrowserMessage } from '@remote-harness/shared';
import type { Db } from './db.js';

export function createBrowserServer(db: Db) {
  const wss = new WebSocketServer({ noServer: true });

  function authorize(req: IncomingMessage): string | null {
    const url = new URL(req.url ?? '', 'http://localhost');
    return db.tenantForApiToken(url.searchParams.get('token') ?? '');
  }

  // A browser only ever hears about its own tenant.
  const clients = new Map<WebSocket, string>();
  wss.on('connection', (ws, req) => {
    const tenantId = authorize(req);
    if (!tenantId) {
      ws.close(1008, 'unauthorized');
      return;
    }
    clients.set(ws, tenantId);
    ws.on('close', () => clients.delete(ws));
  });

  return {
    wss,
    authorize,
    broadcast(tenantId: string, msg: HubToBrowserMessage): void {
      const payload = JSON.stringify(msg);
      for (const [ws, t] of clients) {
        if (t === tenantId && ws.readyState === WebSocket.OPEN) ws.send(payload);
      }
    },
    disconnectTenant(tenantId: string): void {
      for (const [ws, t] of clients) if (t === tenantId) ws.close(1008, 'tenant removed');
    },
  };
}

export type BrowserServer = ReturnType<typeof createBrowserServer>;
