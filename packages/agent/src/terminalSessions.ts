import { getSessionMessages, listSessions, type SDKSessionInfo, type SessionMessage } from '@anthropic-ai/claude-agent-sdk';
import type { AgentToHubMessage } from '@remote-harness/shared';
import { isInside, realpathLoose } from './paths.js';
import type { RegistryEntry, SessionRegistry } from './registry.js';
import { titleFrom } from './sessionManager.js';

// A first import sends only the recent part of a chat, trimmed: transcripts here run to tens of MB, mostly tool output.
// Claude itself still resumes from the full transcript on this machine; this is only what the app displays.
const MAX_BACKFILL = 500;
const MAX_TEXT = 20_000;
const MAX_IMAGE_BASE64 = 300_000;
const DEFAULT_INTERVAL_MS = 60_000;

/**
 * Makes Claude Code sessions run in a terminal on this machine show up in the app: each one inside the workspace is
 * registered (so the app can resume it) and its transcript is sent to the hub, then kept current while it continues
 * in the terminal. Sessions the agent itself is running are skipped; their messages already reach the hub live.
 */
export class TerminalSessionSync {
  private running = false;
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private o: {
      workspaceRoot: string;
      registry: SessionRegistry;
      send: (msg: AgentToHubMessage) => void;
      isLive: (sessionId: string) => boolean;
      accountId: string;
      intervalMs?: number;
      list?: typeof listSessions;
      read?: typeof getSessionMessages;
    },
  ) {}

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => void this.syncOnce(), this.o.intervalMs ?? DEFAULT_INTERVAL_MS);
    this.timer.unref();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async syncOnce(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const root = realpathLoose(this.o.workspaceRoot);
      const infos = await (this.o.list ?? listSessions)({});
      for (const info of infos) {
        if (!info.cwd || !isInside(root, realpathLoose(info.cwd))) continue;
        try {
          await this.syncSession(info);
        } catch (err) {
          console.error(`[terminal-sync] ${info.sessionId}: ${err instanceof Error ? err.message : err}`);
        }
      }
    } catch (err) {
      console.error(`[terminal-sync] ${err instanceof Error ? err.message : err}`);
    } finally {
      this.running = false;
    }
  }

  /** A turn the agent ran has finished: the hub already has its messages, so remember where its transcript stops. */
  async markSynced(sessionId: string, cwd: string): Promise<void> {
    const entry = this.o.registry.get(sessionId);
    if (!entry) return;
    try {
      const msgs = await this.readAll(sessionId, cwd);
      const last = msgs.at(-1)?.uuid;
      if (last) this.o.registry.upsert({ ...entry, syncedUuid: last, syncedMtime: undefined });
    } catch {
      // the next sync baselines it instead
    }
  }

  private async syncSession(info: SDKSessionInfo): Promise<void> {
    const id = info.sessionId;
    const entry = this.o.registry.get(id);
    if (entry?.syncedMtime !== undefined && info.lastModified <= entry.syncedMtime) return;

    const msgs = await this.readAll(id, info.cwd!);
    if (this.o.isLive(id)) {
      // Its messages reach the hub live. Keep the marker at the end of its transcript anyway: the chat stays open until
      // the agent stops, and a marker left behind would resend everything since then after the next start.
      const last = msgs.at(-1)?.uuid;
      if (entry && last) this.o.registry.upsert({ ...entry, syncedUuid: last, syncedMtime: info.lastModified });
      return;
    }

    let next: RegistryEntry;
    let toSend: SessionMessage[];
    if (!entry) {
      next = {
        sessionId: id,
        cwd: realpathLoose(info.cwd!),
        title: titleFrom(info.customTitle || info.summary || info.firstPrompt || ''),
        createdAt: new Date(info.createdAt ?? info.lastModified).toISOString(),
        accountId: this.o.accountId,
        source: 'terminal',
      };
      // tempId = sessionId: the hub stores it like a new chat without aliasing anything, and tells open apps about it.
      this.o.send({ type: 'session_created', tempId: id, sessionId: id, cwd: next.cwd, title: next.title, accountId: next.accountId });
      toSend = msgs.slice(-MAX_BACKFILL);
    } else if (!entry.syncedUuid) {
      // Made by the agent before this sync existed (or it stopped mid-chat): the hub has its messages already.
      next = entry;
      toSend = [];
    } else {
      next = entry;
      const at = msgs.findIndex((m) => m.uuid === entry.syncedUuid);
      // Not found means the transcript was rewound or compacted; resending it all would duplicate the history.
      toSend = at === -1 ? [] : msgs.slice(at + 1);
    }

    for (let i = 0; i < toSend.length; i++) {
      this.o.send({ type: 'sdk_message', sessionId: id, message: slim(toSend[i]) });
      if (i % 100 === 99) await new Promise((r) => setImmediate(r));
    }
    // Any sdk_message marks the session active on the hub; it is not running here.
    if (toSend.length > 0 || !entry) this.o.send({ type: 'session_ended', sessionId: id });

    // Re-read: the person may have changed this chat's mode/model/effort while the messages were going out.
    this.o.registry.upsert({ ...next, ...this.o.registry.get(id), syncedUuid: msgs.at(-1)?.uuid ?? next.syncedUuid, syncedMtime: info.lastModified });
  }

  private readAll(sessionId: string, dir: string): Promise<SessionMessage[]> {
    return (this.o.read ?? getSessionMessages)(sessionId, { dir });
  }
}

/** Copy of a transcript message small enough for the hub: long strings cut, big images replaced by a note. */
export function slim<T>(value: T): T {
  if (typeof value === 'string') {
    return (value.length > MAX_TEXT ? `${value.slice(0, MAX_TEXT)}\n… [${value.length - MAX_TEXT} more characters on the computer]` : value) as T;
  }
  if (Array.isArray(value)) return value.map(slim) as T;
  if (value && typeof value === 'object') {
    const o = value as Record<string, unknown>;
    const src = o.source as { type?: string; data?: unknown } | undefined;
    if (o.type === 'image' && src?.type === 'base64' && typeof src.data === 'string' && src.data.length > MAX_IMAGE_BASE64) {
      return { type: 'text', text: '[image too large to show here]' } as T;
    }
    return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, slim(v)])) as T;
  }
  return value;
}
