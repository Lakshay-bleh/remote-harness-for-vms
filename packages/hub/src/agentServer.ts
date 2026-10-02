import { randomUUID, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { AgentToHubMessage, AgentSessionSummary, ClaudeAccount, HubToAgentMessage } from '@remote-harness/shared';
import { parseAgentFrame } from '@remote-harness/shared/validate';
import { DEFAULT_TENANT, type Db, type MachineScope } from './db.js';

const PROJECTS_REQUEST_TIMEOUT_MS = 5000;

export type AgentEventHandlers = {
  onHello: (tenantId: string, vmId: string, vmName: string, accounts: ClaudeAccount[], sessions: AgentSessionSummary[], agentVersion: string) => void;
  onEvent: (tenantId: string, vmId: string, msg: AgentToHubMessage) => void;
  onStatusChange: (tenantId: string, vmId: string, vmName: string, connected: boolean) => void;
};

export type AgentServerOptions = {
  // How often to ping agents; one that hasn't answered by the next tick is terminated (half-open TCP otherwise reads as OPEN forever).
  pingIntervalMs?: number;
  maxPayloadBytes?: number;
};

const same = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export function createAgentServer(db: Db, defaultToken: string, handlers: AgentEventHandlers, opts: AgentServerOptions = {}) {
  // sdk_message frames can carry tool-result images, hence the generous default; it still bounds what a peer can make us buffer.
  const wss = new WebSocketServer({ noServer: true, maxPayload: opts.maxPayloadBytes ?? 32 * 1024 * 1024 });
  const alive = new WeakMap<WebSocket, boolean>();
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
  }, opts.pingIntervalMs ?? 30_000);
  heartbeat.unref();
  wss.on('close', () => clearInterval(heartbeat));

  /**
   * Which tenant does this agent belong to, and is it limited to one machine? null = refuse. The classic shared token is
   * the default tenant. A machine credential names the one machine it may register as, and stops working when it expires.
   */
  function authorizeScoped(req: IncomingMessage): { tenantId: string; machine?: MachineScope } | null {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) return null;
    if (same(token, defaultToken)) return { tenantId: DEFAULT_TENANT };
    const tenantId = db.tenantForAgentToken(token);
    if (tenantId) return { tenantId };
    const machine = db.machineForAgentToken(token);
    return machine ? { tenantId: machine.tenantId, machine } : null;
  }
  const authorize = (req: IncomingMessage): string | null => authorizeScoped(req)?.tenantId ?? null;

  const byVmId = new Map<string, WebSocket>();
  const tenantOfVm = new Map<string, string>();
  const pendingProjectRequests = new Map<string, { resolve: (projects: string[]) => void }>();
  const tenantOfSocket = new WeakMap<WebSocket, string>();
  const machineOfSocket = new WeakMap<WebSocket, MachineScope>();

  wss.on('connection', (ws, req) => {
    // Authorized during the upgrade; recomputed here from the same request so the socket carries its tenant.
    const auth = authorizeScoped(req);
    if (!auth) {
      ws.close(1008, 'unauthorized');
      return;
    }
    const { tenantId, machine } = auth;
    tenantOfSocket.set(ws, tenantId);
    alive.set(ws, true);
    ws.on('pong', () => alive.set(ws, true));
    // ws emits 'error' (e.g. payload too large) before closing; unhandled, it would take the process down.
    ws.on('error', (err) => console.error('[agent] socket error:', err.message));
    let vmId: string | null = null;
    let vmName: string | null = null;
    if (machine) {
      machineOfSocket.set(ws, machine);
      // A machine credential ends on its own: hang up when it does, so a copy of it cannot keep a session open.
      const timer = setTimeout(() => ws.close(1008, 'credential expired'), Math.max(0, Date.parse(machine.expiresAt) - Date.now()));
      ws.on('close', () => clearTimeout(timer));
    }

    ws.on('message', (data) => {
      const msg = parseAgentFrame(data.toString());
      if (!msg) return; // not JSON, not an object, or not a frame we know: ignore it
      try {
        handleFrame(msg);
      } catch (err) {
        // One bad frame (or a storage failure) must never take the hub down for every tenant.
        console.error('[agent] dropped frame after handler error:', err);
      }
    });

    function handleFrame(msg: AgentToHubMessage) {
      const t = db.for(tenantId);

      if (msg.type === 'hello') {
        if (machine && msg.vmName !== machine.vmName) {
          // This credential is for one machine. Registering as another would put a process where it was not sent.
          ws.close(1008, 'wrong machine');
          return;
        }
        // One socket speaks for exactly one VM; a second identity would leave stale registry entries behind.
        if (vmName !== null && msg.vmName !== vmName) {
          ws.close(1008, 'hello identity changed');
          return;
        }
        const nextId = t.upsertVm(msg.vmName);
        const previous = byVmId.get(nextId);
        if (previous && previous !== ws) {
          // Two live agents with the same name (cloned VMs) would otherwise kick each other off forever. Refuse the newcomer;
          // a dead previous connection is reaped by the heartbeat and the agent's own reconnect loop then gets in.
          if (previous.readyState === WebSocket.OPEN && alive.get(previous) !== false) {
            ws.close(1008, 'VM name already connected');
            return;
          }
          previous.terminate();
        }
        vmName = msg.vmName;
        vmId = nextId;
        byVmId.set(vmId, ws);
        tenantOfVm.set(vmId, tenantId);
        handlers.onHello(tenantId, vmId, vmName, msg.accounts, msg.sessions, String(msg.agentVersion ?? ''));
        handlers.onStatusChange(tenantId, vmId, vmName, true);
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

      handlers.onEvent(tenantId, vmId, msg);
    }

    ws.on('close', () => {
      if (vmId && vmName) {
        if (byVmId.get(vmId) === ws) {
          byVmId.delete(vmId);
          tenantOfVm.delete(vmId);
        }
        handlers.onStatusChange(tenantId, vmId, vmName, false);
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
      ws.send(JSON.stringify(msg));
      return true;
    },
    connectedVmIds(tenantId: string): string[] {
      return [...byVmId.keys()].filter((id) => tenantOfVm.get(id) === tenantId);
    },
    /** Hang up the agent that registered as this machine of the tenant (its credentials were revoked). */
    disconnectMachine(tenantId: string, vmName: string): void {
      for (const [vmId, ws] of byVmId) {
        const m = machineOfSocket.get(ws);
        if (tenantOfVm.get(vmId) === tenantId && m?.vmName === vmName) ws.close(1008, 'credential revoked');
      }
    },
    /** Hang up every agent of a tenant, e.g. when it is deleted or its agent token rotated. */
    disconnectTenant(tenantId: string): void {
      for (const [vmId, ws] of byVmId) {
        if (tenantOfVm.get(vmId) === tenantId) ws.close(1008, 'tenant removed');
      }
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
