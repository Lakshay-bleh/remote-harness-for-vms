import { randomUUID, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { AgentToHubMessage, AgentSessionSummary, ClaudeAccount, HubToAgentMessage } from '@remote-harness/shared';
import { DEFAULT_TENANT, type Db, type MachineScope } from './db.js';

const PROJECTS_REQUEST_TIMEOUT_MS = 5000;

export type AgentEventHandlers = {
  onHello: (tenantId: string, vmId: string, vmName: string, accounts: ClaudeAccount[], sessions: AgentSessionSummary[], agentVersion: string) => void;
  onEvent: (tenantId: string, vmId: string, msg: AgentToHubMessage) => void;
  onStatusChange: (tenantId: string, vmId: string, vmName: string, connected: boolean) => void;
};

const same = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export function createAgentServer(db: Db, defaultToken: string, handlers: AgentEventHandlers) {
  const wss = new WebSocketServer({ noServer: true });

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
    let vmId: string | null = null;
    let vmName: string | null = null;
    if (machine) {
      machineOfSocket.set(ws, machine);
      // A machine credential ends on its own: hang up when it does, so a copy of it cannot keep a session open.
      const timer = setTimeout(() => ws.close(1008, 'credential expired'), Math.max(0, Date.parse(machine.expiresAt) - Date.now()));
      ws.on('close', () => clearTimeout(timer));
    }

    ws.on('message', (data) => {
      let msg: AgentToHubMessage;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      const t = db.for(tenantId);

      if (msg.type === 'hello') {
        if (machine && msg.vmName !== machine.vmName) {
          // This credential is for one machine. Registering as another would put a process where it was not sent.
          ws.close(1008, 'wrong machine');
          return;
        }
        vmName = msg.vmName;
        vmId = t.upsertVm(vmName);
        const previous = byVmId.get(vmId);
        if (previous && previous !== ws) previous.close();
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
    });

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
