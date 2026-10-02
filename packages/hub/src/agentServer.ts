import { randomUUID } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { AgentToHubMessage, AgentSessionSummary, ClaudeAccount, HubToAgentMessage, HubUserInput, McpServerConfig } from '@remote-harness/shared';
import type { Db } from './db.js';
import { parseAgentFrame } from '@remote-harness/shared/validate';

const PROJECTS_REQUEST_TIMEOUT_MS = 5000;

export type AgentEventHandlers = {
  onHello: (vmId: string, vmName: string, accounts: ClaudeAccount[], sessions: AgentSessionSummary[]) => void;
  onEvent: (vmId: string, msg: AgentToHubMessage) => void;
  onStatusChange: (vmId: string, vmName: string, connected: boolean) => void;
};

function withMcpServers(db: Db, msg: HubUserInput): HubUserInput {
  const servers = db.listMcpServers();
  if (servers.length === 0) return msg;
  const mcpServers: Record<string, McpServerConfig> = {};
  for (const s of servers) mcpServers[s.name] = { type: 'http', url: s.url, headers: { Authorization: `Bearer ${s.token}` } };
  return { ...msg, mcpServers };
}

export type AgentServerOptions = {
  // How often to ping agents; an agent that hasn't answered by the next tick is terminated.
  pingIntervalMs?: number;
  maxPayloadBytes?: number;
};

const DEFAULT_PING_INTERVAL_MS = 30_000;
const DEFAULT_MAX_PAYLOAD_BYTES = 32 * 1024 * 1024; // sdk_message frames can carry tool-result images

export function createAgentServer(db: Db, token: string, handlers: AgentEventHandlers, opts: AgentServerOptions = {}) {
  const wss = new WebSocketServer({ noServer: true, maxPayload: opts.maxPayloadBytes ?? DEFAULT_MAX_PAYLOAD_BYTES });
  const pingIntervalMs = opts.pingIntervalMs ?? DEFAULT_PING_INTERVAL_MS;

  function authorize(req: IncomingMessage): boolean {
    return req.headers.authorization === `Bearer ${token}`;
  }

  const byVmId = new Map<string, WebSocket>();
  const pendingProjectRequests = new Map<string, { resolve: (projects: string[]) => void }>();

  const alive = new WeakMap<WebSocket, boolean>();

  // A crashed VM or dropped network leaves a half-open TCP connection that still reads as OPEN.
  // Ping every agent; one that hasn't answered since the previous tick is terminated.
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (alive.get(ws) === false) {
        ws.terminate();
        continue;
      }
      alive.set(ws, false);
      try {
        ws.ping();
      } catch {
        ws.terminate();
      }
    }
  }, pingIntervalMs);
  heartbeat.unref();
  wss.on('close', () => clearInterval(heartbeat));

  wss.on('connection', (ws) => {
    let vmId: string | null = null;
    let vmName: string | null = null;
    alive.set(ws, true);
    ws.on('pong', () => alive.set(ws, true));
    ws.on('error', (err) => console.error('[agent] socket error:', err.message));

    ws.on('message', (data) => {
      const msg = parseAgentFrame(data.toString());
      if (!msg) return;
      try {
        handleFrame(msg);
      } catch (err) {
        // One bad frame (or a handler/db failure) must never take the hub down for every tenant.
        console.error('[agent] dropped frame after handler error:', err);
      }
    });

    function handleFrame(msg: AgentToHubMessage) {
      if (msg.type === 'hello') {
        // One socket speaks for exactly one VM; a second identity would leave stale registry entries.
        if (vmName !== null && msg.vmName !== vmName) {
          ws.close(1008, 'hello identity changed');
          return;
        }
        const nextId = db.upsertVm(msg.vmName);
        const previous = byVmId.get(nextId);
        if (previous && previous !== ws) {
          // Two live agents with the same name (cloned VMs) would otherwise kick each other forever.
          // Refuse the newcomer; a genuinely dead previous connection is reaped by the heartbeat and
          // the agent's own reconnect loop then gets in.
          if (previous.readyState === WebSocket.OPEN && alive.get(previous) !== false) {
            ws.close(1008, 'VM name already connected');
            return;
          }
          previous.terminate();
        }
        vmName = msg.vmName;
        vmId = nextId;
        byVmId.set(vmId, ws);
        handlers.onHello(vmId, vmName, msg.accounts, msg.sessions);
        handlers.onStatusChange(vmId, vmName, true);
        return;
      }

      if (!vmId) return; // must hello first

      if (msg.type === 'projects_list') {
        const pending = pendingProjectRequests.get(msg.requestId);
        if (pending) {
          pendingProjectRequests.delete(msg.requestId);
          pending.resolve(msg.projects);
        }
        return;
      }

      handlers.onEvent(vmId, msg);
    }

    ws.on('close', () => {
      if (vmId && vmName) {
        if (byVmId.get(vmId) === ws) byVmId.delete(vmId);
        handlers.onStatusChange(vmId, vmName, false);
      }
    });
  });

  return {
    wss,
    authorize,
    isConnected(vmId: string): boolean {
      return byVmId.has(vmId);
    },
    sendToVm(vmId: string, msg: HubToAgentMessage): boolean {
      const ws = byVmId.get(vmId);
      if (!ws || ws.readyState !== WebSocket.OPEN) return false;
      ws.send(JSON.stringify(msg.type === 'user_input' ? withMcpServers(db, msg) : msg));
      return true;
    },
    connectedVmIds(): string[] {
      return [...byVmId.keys()];
    },
    requestProjects(vmId: string): Promise<string[]> {
      const ws = byVmId.get(vmId);
      if (!ws || ws.readyState !== WebSocket.OPEN) return Promise.resolve([]);
      const requestId = randomUUID();
      ws.send(JSON.stringify({ type: 'list_projects', requestId }));
      return new Promise((resolve) => {
        const timer = setTimeout(() => {
          pendingProjectRequests.delete(requestId);
          resolve([]);
        }, PROJECTS_REQUEST_TIMEOUT_MS);
        pendingProjectRequests.set(requestId, {
          resolve: (projects) => {
            clearTimeout(timer);
            resolve(projects);
          },
        });
      });
    },
  };
}

export type AgentServer = ReturnType<typeof createAgentServer>;
