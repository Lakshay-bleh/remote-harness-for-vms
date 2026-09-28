import type { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { AgentToHubMessage, AgentSessionSummary, ClaudeAccount, HubToAgentMessage } from '@remote-harness/shared';
import type { Db } from './db.js';

export type AgentEventHandlers = {
  onHello: (vmId: string, vmName: string, accounts: ClaudeAccount[], sessions: AgentSessionSummary[]) => void;
  onEvent: (vmId: string, msg: AgentToHubMessage) => void;
  onStatusChange: (vmId: string, vmName: string, connected: boolean) => void;
};

export function createAgentServer(db: Db, token: string, handlers: AgentEventHandlers) {
  const wss = new WebSocketServer({ noServer: true });

  function authorize(req: IncomingMessage): boolean {
    return req.headers.authorization === `Bearer ${token}`;
  }

  const byVmId = new Map<string, WebSocket>();

  wss.on('connection', (ws) => {
    let vmId: string | null = null;
    let vmName: string | null = null;

    ws.on('message', (data) => {
      let msg: AgentToHubMessage;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }

      if (msg.type === 'hello') {
        vmName = msg.vmName;
        vmId = db.upsertVm(vmName);
        const previous = byVmId.get(vmId);
        if (previous && previous !== ws) previous.close();
        byVmId.set(vmId, ws);
        handlers.onHello(vmId, vmName, msg.accounts, msg.sessions);
        handlers.onStatusChange(vmId, vmName, true);
        return;
      }

      if (!vmId) return; // must hello first
      handlers.onEvent(vmId, msg);
    });

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
      ws.send(JSON.stringify(msg));
      return true;
    },
    connectedVmIds(): string[] {
      return [...byVmId.keys()];
    },
  };
}

export type AgentServer = ReturnType<typeof createAgentServer>;
