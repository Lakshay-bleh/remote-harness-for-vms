import { mkdtempSync, rmSync } from 'node:fs';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import express from 'express';
import type { HubToAgentMessage, HubToBrowserMessage } from '@remote-harness/shared';
import { RateLimiter } from '@remote-harness/shared/validate';
import { openDb, type Db } from './db.js';
import { createApiRouter } from './api.js';
import type { AgentServer } from './agentServer.js';
import type { BrowserServer } from './browserServer.js';

export const APP_PASSWORD = 'correct-horse-battery-staple-1234';

export type ApiHarness = {
  base: string;
  db: Db;
  token: string;
  sent: HubToAgentMessage[];
  broadcasts: HubToBrowserMessage[];
  state: { connected: boolean };
  call: (method: string, path: string, body?: unknown, opts?: { token?: string | null; headers?: Record<string, string>; raw?: string }) => Promise<{ status: number; body: any; headers: Headers }>;
  close: () => Promise<void>;
};

// Real express router + real sqlite; only the two socket servers are stubbed (they are I/O boundaries
// whose outputs we record).
export async function startApi(opts: { maxLoginFailures?: number; trustProxy?: boolean; allowPrivateMcp?: boolean } = {}): Promise<ApiHarness> {
  const dir = mkdtempSync(join(tmpdir(), 'hub-api-test-'));
  const db = openDb(dir);
  const sent: HubToAgentMessage[] = [];
  const broadcasts: HubToBrowserMessage[] = [];
  const state = { connected: true };

  const agentServer = {
    isConnected: () => state.connected,
    sendToVm: (_vm: string, msg: HubToAgentMessage) => {
      if (!state.connected) return false;
      sent.push(msg);
      return true;
    },
    requestProjects: async () => [],
    connectedVmIds: () => [],
  } as unknown as AgentServer;
  const browserServer = {
    broadcast: (m: HubToBrowserMessage) => broadcasts.push(m),
    closeRevokedSessions: () => {},
  } as unknown as BrowserServer;

  const app = express();
  app.use('/api', createApiRouter(db, agentServer, browserServer, APP_PASSWORD, {
    escanorApiUrl: 'http://127.0.0.1:1',
    allowedEmails: [],
    trustProxy: opts.trustProxy ?? false,
    allowPrivateMcp: opts.allowPrivateMcp ?? false,
    loginLimiter: new RateLimiter({ maxFailures: opts.maxLoginFailures ?? 5, windowMs: 60_000 }),
  }));
  const http: Server = createServer(app);
  await new Promise<void>((r) => http.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${(http.address() as AddressInfo).port}`;
  const token = db.createAuthToken();

  async function call(method: string, path: string, body?: unknown, o: { token?: string | null; headers?: Record<string, string>; raw?: string } = {}) {
    const headers: Record<string, string> = { ...(o.headers ?? {}) };
    const t = o.token === undefined ? token : o.token;
    if (t) headers.authorization = `Bearer ${t}`;
    let payload: string | undefined;
    if (o.raw !== undefined) payload = o.raw;
    else if (body !== undefined) payload = JSON.stringify(body);
    if (payload !== undefined) headers['content-type'] = 'application/json';
    const res = await fetch(`${base}/api${path}`, { method, headers, body: payload });
    const text = await res.text();
    let parsed: any = text;
    try { parsed = text ? JSON.parse(text) : null; } catch { /* leave as text */ }
    return { status: res.status, body: parsed, headers: res.headers };
  }

  return {
    base, db, token, sent, broadcasts, state, call,
    close: async () => {
      http.closeAllConnections();
      await new Promise((r) => http.close(r));
      rmSync(dir, { recursive: true, force: true });
    },
  };
}
