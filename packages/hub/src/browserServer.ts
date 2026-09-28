import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { HubToBrowserMessage } from '@remote-harness/shared';
import type { Db } from './db.js';

export function createBrowserServer(db: Db) {
  const wss = new WebSocketServer({ noServer: true });

  function authorize(req: IncomingMessage): boolean {
    const url = new URL(req.url ?? '', 'http://localhost');
    return db.isValidToken(url.searchParams.get('token') ?? '');
  }

  const clients = new Set<WebSocket>();
  wss.on('connection', (ws) => {
    clients.add(ws);
    ws.on('close', () => clients.delete(ws));
  });

  return {
    wss,
    authorize,
    broadcast(msg: HubToBrowserMessage): void {
      const payload = JSON.stringify(msg);
      for (const ws of clients) {
        if (ws.readyState === WebSocket.OPEN) ws.send(payload);
      }
    },
  };
}

export type BrowserServer = ReturnType<typeof createBrowserServer>;
