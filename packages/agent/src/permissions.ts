import { randomUUID } from 'node:crypto';
import type { AgentToHubMessage, PermissionDecision } from '@remote-harness/shared';

type Decision = { behavior: PermissionDecision; message?: string };
type Pending = { sessionKey: string; resolve: (d: Decision) => void };

// Tracks tool-permission requests awaiting a human decision. Every path out of "pending" is covered:
// the hub answers, the call is aborted (including already aborted), or the session ends.
export class PermissionBroker {
  private pending = new Map<string, Pending>();

  constructor(private send: (msg: AgentToHubMessage) => void) {}

  request(
    sessionKey: string,
    toolName: string,
    input: Record<string, unknown>,
    blockedPath: string | undefined,
    signal: AbortSignal,
  ): Promise<Decision> {
    if (signal.aborted) return Promise.resolve({ behavior: 'deny', message: 'Interrupted' });
    const requestId = randomUUID();
    this.send({ type: 'permission_request', sessionId: sessionKey, requestId, toolName, input, blockedPath });
    return new Promise((resolve) => {
      this.pending.set(requestId, { sessionKey, resolve });
      signal.addEventListener(
        'abort',
        () => {
          if (this.pending.delete(requestId)) resolve({ behavior: 'deny', message: 'Interrupted' });
        },
        { once: true },
      );
    });
  }

  resolve(requestId: string, behavior: PermissionDecision, message?: string): void {
    const p = this.pending.get(requestId);
    if (!p) return;
    this.pending.delete(requestId);
    p.resolve({ behavior, message });
  }

  dropSession(sessionKey: string): void {
    for (const [id, p] of this.pending) {
      if (p.sessionKey !== sessionKey) continue;
      this.pending.delete(id);
      p.resolve({ behavior: 'deny', message: 'Session ended' });
    }
  }

  pendingCount(): number {
    return this.pending.size;
  }
}
