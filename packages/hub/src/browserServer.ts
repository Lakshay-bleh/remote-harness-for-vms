import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { HubToBrowserMessage } from '@remote-harness/shared';
import type { Db } from './db.js';

export function createBrowserServer(db: Db) {
  const wss = new WebSocketServer({
    noServer: true,
    // Browsers only ever send a 4-byte "ping"; anything large is abuse.
    maxPayload: 16 * 1024,
    // Never echo the credential protocol in the upgrade response.
    handleProtocols: (protocols) => protocols.has('escanor.hub.v1') ? 'escanor.hub.v1' : false,
  });

  function requestToken(req: IncomingMessage): string {
    const protocols = (req.headers['sec-websocket-protocol'] ?? '').split(',').map(value => value.trim());
    const credential = protocols.find(value => value.startsWith('escanor.auth.'));
    // Retain old clients during rollout; new clients keep credentials out of URLs.
    return credential ? credential.slice('escanor.auth.'.length)
      : new URL(req.url ?? '', 'http://localhost').searchParams.get('token') ?? '';
  }

  function authorize(req: IncomingMessage): boolean {
    return db.isValidToken(requestToken(req));
  }

  const clients = new Set<WebSocket>();
  const credentials = new WeakMap<WebSocket, string>();
  wss.on('connection', (ws, req) => {
    credentials.set(ws, requestToken(req));
    clients.add(ws);
    // ws emits 'error' (e.g. payload too large) before closing; unhandled, it would crash the process.
    ws.on('error', (err) => console.error('[browser] socket error:', err.message));
    ws.on('close', () => clients.delete(ws));
  });

  return {
    wss,
    authorize,
    closeRevokedSessions(): void {
      for (const ws of clients) {
        if (!db.isValidToken(credentials.get(ws) ?? '')) ws.close(1008, 'Session expired or revoked');
      }
    },
    broadcast(msg: HubToBrowserMessage): void {
      const payload = JSON.stringify(msg);
      for (const ws of clients) {
        if (!db.isValidToken(credentials.get(ws) ?? '')) {
          ws.close(1008, 'Session expired or revoked');
          continue;
        }
        if (ws.readyState === WebSocket.OPEN) ws.send(payload);
      }
    },
  };
}

export type BrowserServer = ReturnType<typeof createBrowserServer>;
