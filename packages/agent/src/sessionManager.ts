import { query as sdkQuery, type McpServerConfig, type Options, type SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { isValidMcpServerName } from '@remote-harness/shared';
import { isSandboxAutoAllowed } from './sandboxPolicy.js';
import { isAutoAllowedMcpTool } from './mcpApproval.js';
import { childEnv } from './childEnv.js';
import { PermissionBroker } from './permissions.js';
import { resolveInside } from './paths.js';
import type {
  AgentMcpServerStatus,
  AgentSessionSummary,
  AgentToHubMessage,
  EffortLevel,
  HubUserInput,
  ImageAttachment,
  ManagedMcpServer,
  PermissionDecision,
  PermissionMode,
} from '@remote-harness/shared';
import { AsyncMessageQueue } from './queue.js';
import { SessionRegistry } from './registry.js';
import type { ClaudeProfile } from './profiles.js';

type LiveSession = {
  queue: AsyncMessageQueue<SDKUserMessage>;
  cwd: string;
  interrupt: () => Promise<unknown>;
  setPermissionMode: (mode: PermissionMode) => Promise<void>;
  setModel: (model?: string) => Promise<void>;
  setEffort: (effort: EffortLevel | null) => Promise<void>;
  setMcpServers: (servers: Record<string, McpServerConfig>) => Promise<unknown>;
  mcpServerStatus: () => Promise<Array<{ name: string; status: string; error?: string }>>;
  close: () => void;
  appliedMcp: string; // the MCP config this session was last given, so an unchanged re-push is a no-op
};

// A wedged session must not stop the rest (or the status report) from converging.
const MCP_APPLY_TIMEOUT_MS = 15_000;

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out after ${ms}ms`)), ms);
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

function toUserMessage(text: string, images: ImageAttachment[] | undefined): SDKUserMessage {
  const content: Array<Record<string, unknown>> = [];
  if (text) content.push({ type: 'text', text });
  for (const img of images ?? []) {
    content.push({
      type: 'image',
      source: { type: 'base64', media_type: img.mediaType, data: img.dataBase64 },
    });
  }
  return {
    type: 'user',
    message: { role: 'user', content: content as never },
    parent_tool_use_id: null,
  };
}

function titleFrom(text: string): string {
  const oneLine = text.trim().replace(/\s+/g, ' ');
  return oneLine.length > 60 ? `${oneLine.slice(0, 57)}...` : oneLine || 'New session';
}

export class SessionManager {
  private live = new Map<string, LiveSession>();
  private permissions: PermissionBroker;
  private registry: SessionRegistry;
  // The hub's declarative set of MCP servers. Every session, new or already running, is made to match it.
  private mcpServers = new Map<string, ManagedMcpServer>();
  // What each running session's own MCP client last reported, so the hub can show real connection state.
  private mcpSessionStatus = new Map<LiveSession, Map<string, { status: string; error?: string }>>();
  private lastMcpReport = '';

  constructor(
    private workspaceRoot: string,
    dataDir: string,
    private profiles: ClaudeProfile[],
    private send: (msg: AgentToHubMessage) => void,
    private opts: {
      managed?: boolean;
      guide?: string;
      mcpOverride?: Omit<ManagedMcpServer, 'updatedAt'> | null;
      /** Directories the sandbox policy never lets the assistant change on its own (the agent's code, data and .env). */
      protectedPaths?: string[];
      /** Hosts WebFetch may reach without a card in a managed worker. */
      fetchAllow?: string[];
      /** The SDK's query(); injectable so tests can see exactly what a session is started with. */
      query?: typeof sdkQuery;
    } = {},
  ) {
    this.registry = new SessionRegistry(dataDir);
    this.permissions = new PermissionBroker((msg) => this.send(msg));
    // Present from the first session on, before the hub has pushed anything.
    if (opts.mcpOverride) this.mcpServers.set(opts.mcpOverride.name, { ...opts.mcpOverride, updatedAt: new Date().toISOString() });
  }

  private resolveProfile(accountId: string | undefined): ClaudeProfile {
    return this.profiles.find((p) => p.id === accountId) ?? this.profiles[0];
  }

  summaries(): AgentSessionSummary[] {
    return this.registry.all().map((e) => ({
      sessionId: e.sessionId,
      cwd: e.cwd,
      title: e.title,
      createdAt: e.createdAt,
      status: this.live.has(e.sessionId) ? 'active' : 'idle',
      accountId: e.accountId,
    }));
  }

  private resolveCwd(requested: string | undefined): string {
    // Symlink-aware: a link inside the workspace pointing outside it does not make the outside part of the workspace.
    return resolveInside(this.workspaceRoot, requested);
  }

  // ---------- hub-managed MCP servers ----------

  private sdkMcpConfig(): Record<string, McpServerConfig> {
    const out: Record<string, McpServerConfig> = {};
    for (const s of this.mcpServers.values()) {
      out[s.name] = {
        type: 'http',
        url: s.url,
        ...(s.headers && Object.keys(s.headers).length > 0 ? { headers: s.headers } : {}),
        // Escanor exposes a handful of tools, so have them in the very first prompt instead of
        // deferred behind tool search: "available automatically" means the model can call them at once.
        ...(s.alwaysLoad !== false ? { alwaysLoad: true } : {}),
      };
    }
    return out;
  }

  // Decided per call, from the *current* set (see mcpApproval.ts), so turning auto-approve off takes effect in chats already open.
  private isAutoAllowedMcpTool(toolName: string, input: Record<string, unknown>): boolean {
    return isAutoAllowedMcpTool(this.mcpServers.values(), toolName, input);
  }

  /** Replace the managed MCP servers and make every running session match, without restarting it. */
  async setMcpServers(servers: ManagedMcpServer[]): Promise<void> {
    const next = new Map<string, ManagedMcpServer>();
    for (const s of servers) {
      // The hub validates already; a bad entry here must never reach a session's config.
      if (/^https?:\/\//.test(s.url) && isValidMcpServerName(s.name)) next.set(s.name, s);
    }
    // This machine's own entry wins over the hub's of the same name, and is never dropped by a push that omits it.
    if (this.opts.mcpOverride) next.set(this.opts.mcpOverride.name, { ...this.opts.mcpOverride, updatedAt: new Date().toISOString() });
    this.mcpServers = next;
    const config = this.sdkMcpConfig();
    const configJson = JSON.stringify(config);

    const sessions = new Set(this.live.values());
    let applied = 0;
    await Promise.all(
      [...this.live.entries()].map(async ([key, session]) => {
        if (!sessions.delete(session)) return; // the same session is briefly registered under two keys
        try {
          if (session.appliedMcp !== configJson) {
            await withTimeout(session.setMcpServers(config), MCP_APPLY_TIMEOUT_MS);
            session.appliedMcp = configJson;
          }
          const status = await withTimeout(session.mcpServerStatus(), MCP_APPLY_TIMEOUT_MS);
          this.mcpSessionStatus.set(session, new Map(status.map((s) => [s.name, { status: s.status, error: s.error }])));
          applied++;
        } catch (err) {
          console.error(`Could not apply MCP servers to session ${key}:`, err instanceof Error ? err.message : err);
        }
      }),
    );
    this.reportMcpStatus(applied);
  }

  // Keyed by the session object, not its id: a new chat is re-keyed from its temp id to its real one
  // straight after init, and a lookup by the old key would find nothing.
  private refreshMcpStatusLater(session: LiveSession, attempt = 0): void {
    setTimeout(async () => {
      if (![...this.live.values()].includes(session)) return;
      try {
        const status = await withTimeout(session.mcpServerStatus(), MCP_APPLY_TIMEOUT_MS);
        this.mcpSessionStatus.set(session, new Map(status.map((s) => [s.name, { status: s.status, error: s.error }])));
        this.reportMcpStatus();
        if (status.some((s) => s.status === 'pending') && attempt < 4) this.refreshMcpStatusLater(session, attempt + 1);
      } catch {
        // the session ended or is busy; the next init or change reports again
      }
    }, 3000);
  }

  private reportMcpStatus(liveSessions = this.live.size): void {
    const servers: AgentMcpServerStatus[] = [...this.mcpServers.keys()].map((name) => {
      const reports = [...this.mcpSessionStatus.values()].map((m) => m.get(name)).filter((r) => r !== undefined);
      if (reports.length === 0) return { name, status: 'configured' };
      // One healthy session is proof the server works from this VM; otherwise show the most recent problem.
      const best = reports.find((r) => r.status === 'connected') ?? reports[reports.length - 1];
      return { name, status: best.status as AgentMcpServerStatus['status'], ...(best.error ? { error: best.error } : {}) };
    });
    const payload = JSON.stringify({ servers, liveSessions });
    if (payload === this.lastMcpReport) return;
    this.lastMcpReport = payload;
    this.send({ type: 'mcp_status', servers, liveSessions });
  }

  /** Stop every running Claude Code process. Without this they outlive the agent that started them. */
  shutdown(): void {
    for (const session of new Set(this.live.values())) {
      try {
        session.close();
      } catch {
        // already gone
      }
    }
  }

  /** The hub (re)connected: it has forgotten what we last told it. */
  resetMcpReport(): void {
    this.lastMcpReport = '';
  }

  handleUserInput(input: HubUserInput): void {
    const live = this.live.get(input.sessionId);
    if (live) {
      live.queue.push(toUserMessage(input.text, input.images));
      return;
    }
    // Without a tempId this is a resume. If this VM has no record of the session, starting one would create a conversation
    // the hub never learns about (no session_created is sent) and silently drop the history.
    if (!input.tempId && !this.registry.get(input.sessionId)) {
      this.send({
        type: 'error',
        sessionId: input.sessionId,
        message: `Unknown session ${input.sessionId}: this VM has no record of it, so no new conversation was started.`,
      });
      return;
    }
    this.startSession(input);
  }

  private startSession(input: HubUserInput): void {
    const tempId = input.tempId;
    const existingEntry = this.registry.get(input.sessionId);
    const isResume = Boolean(existingEntry) && !tempId;
    const cwd = this.resolveCwd(input.cwd ?? existingEntry?.cwd);
    const profile = this.resolveProfile(isResume ? existingEntry?.accountId : input.accountId);

    let resolvedSessionId = isResume ? input.sessionId : '';
    const queue = new AsyncMessageQueue<SDKUserMessage>();
    const options: Options = {
      cwd,
      permissionMode: 'default',
      // Ask for summarized thinking so the web UI can show it like the CLI's transcript view.
      thinking: { type: 'adaptive', display: 'summarized' },
      // Session config is built from the *current* managed set, so a chat opened after the hub
      // changed it gets the change with no restart.
      mcpServers: this.sdkMcpConfig(),
      // Only the servers above. Without this the CLI also loads a project's own .mcp.json, and a repo that declares a server
      // called "escanor" would inherit the approvals meant for the real one (approval is decided by name).
      strictMcpConfig: true,
      canUseTool: async (toolName, toolInput, opts) => {
        if (this.isAutoAllowedMcpTool(toolName, toolInput)) return { behavior: 'allow' as const, updatedInput: toolInput };
        // A managed worker is a sandbox: local work runs freely, so the assistant can edit, run and fix in a loop.
        if (this.opts.managed && isSandboxAutoAllowed(toolName, toolInput, { root: this.workspaceRoot, protectedPaths: this.opts.protectedPaths, fetchAllow: this.opts.fetchAllow })) {
          return { behavior: 'allow' as const, updatedInput: toolInput };
        }
        const decision = await this.permissions.request(
          resolvedSessionId || tempId || '',
          toolName,
          toolInput,
          opts.blockedPath,
          opts.signal,
        );
        return decision.behavior === 'allow'
          ? { behavior: 'allow' as const, updatedInput: toolInput }
          : { behavior: 'deny' as const, message: decision.message ?? 'Denied by user' };
      },
    };
    if (this.opts.guide) options.systemPrompt = { type: 'preset', preset: 'claude_code', append: this.opts.guide };
    if (isResume) options.resume = input.sessionId;
    // Always built here: the Claude process runs model-chosen shell commands, so it must not inherit the hub credentials.
    options.env = childEnv(process.env, profile.configDir ? { CLAUDE_CONFIG_DIR: profile.configDir } : {});

    const q = (this.opts.query ?? sdkQuery)({ prompt: queue, options });
    queue.push(toUserMessage(input.text, input.images));

    const liveKey = tempId ?? input.sessionId;
    const session: LiveSession = {
      queue,
      cwd,
      interrupt: () => q.interrupt(),
      setPermissionMode: (mode) => q.setPermissionMode(mode),
      setModel: (model) => q.setModel(model),
      setEffort: (effort) => q.applyFlagSettings({ effortLevel: effort }),
      setMcpServers: (servers) => q.setMcpServers(servers),
      mcpServerStatus: () => q.mcpServerStatus(),
      close: () => q.close(),
      appliedMcp: JSON.stringify(options.mcpServers ?? {}),
    };
    this.live.set(liveKey, session);

    void this.pump(q, {
      session,
      tempId,
      cwd,
      accountId: profile.id,
      seedTitle: input.text,
      liveKey,
      getSessionId: () => resolvedSessionId,
      setSessionId: (id) => (resolvedSessionId = id),
    });
  }

  private async pump(
    q: AsyncIterable<unknown>,
    ctx: {
      session: LiveSession;
      tempId?: string;
      cwd: string;
      accountId: string;
      seedTitle: string;
      liveKey: string;
      getSessionId: () => string;
      setSessionId: (id: string) => void;
    },
  ): Promise<void> {
    try {
      for await (const message of q) {
        const msg = message as {
          type?: string;
          subtype?: string;
          session_id?: string;
          mcp_servers?: Array<{ name: string; status: string; error?: string }>;
        };
        if (msg.type === 'system' && msg.subtype === 'init' && Array.isArray(msg.mcp_servers)) {
          this.mcpSessionStatus.set(ctx.session, new Map(msg.mcp_servers.map((s) => [s.name, { status: s.status, error: s.error }])));
          this.reportMcpStatus();
          // MCP servers connect in the background, so init can say 'pending'. Ask again once they have
          // had time to settle, or the hub would show "pending" for as long as the chat stays open.
          if (msg.mcp_servers.some((s) => s.status === 'pending')) this.refreshMcpStatusLater(ctx.session);
        }
        if (msg.type === 'system' && msg.subtype === 'init' && msg.session_id && !ctx.getSessionId()) {
          const sessionId = msg.session_id;
          ctx.setSessionId(sessionId);
          const title = titleFrom(ctx.seedTitle);
          this.registry.upsert({ sessionId, cwd: ctx.cwd, title, createdAt: new Date().toISOString(), accountId: ctx.accountId });
          if (ctx.liveKey !== sessionId) {
            const entry = this.live.get(ctx.liveKey);
            if (entry) {
              this.live.delete(ctx.liveKey);
              this.live.set(sessionId, entry);
            }
          }
          if (ctx.tempId) {
            this.send({ type: 'session_created', tempId: ctx.tempId, sessionId, cwd: ctx.cwd, title, accountId: ctx.accountId });
          }
        }
        this.send({
          type: 'sdk_message',
          sessionId: ctx.getSessionId() || ctx.tempId || ctx.liveKey,
          tempId: ctx.tempId,
          message,
        });
      }
    } catch (err) {
      this.send({
        type: 'error',
        sessionId: ctx.getSessionId() || undefined,
        tempId: ctx.tempId,
        message: err instanceof Error ? err.message : String(err),
      });
    } finally {
      const sessionId = ctx.getSessionId();
      // Cards still waiting for an answer belong to a session that no longer exists: deny them and drop the entries.
      for (const key of new Set([sessionId, ctx.tempId, ctx.liveKey])) if (key) this.permissions.dropSession(key);
      this.live.delete(ctx.liveKey);
      if (sessionId) this.live.delete(sessionId);
      this.mcpSessionStatus.delete(ctx.session);
      this.reportMcpStatus();
      this.send({ type: 'session_ended', sessionId: sessionId || ctx.tempId || ctx.liveKey });
    }
  }

  resolvePermission(requestId: string, behavior: PermissionDecision, message?: string): void {
    this.permissions.resolve(requestId, behavior, message);
  }

  interrupt(sessionId: string): void {
    void this.live.get(sessionId)?.interrupt();
  }

  setPermissionMode(sessionId: string, mode: PermissionMode): void {
    void this.live.get(sessionId)?.setPermissionMode(mode);
  }

  setModel(sessionId: string, model: string | undefined): void {
    void this.live.get(sessionId)?.setModel(model);
  }

  setEffort(sessionId: string, effort: EffortLevel | null): void {
    void this.live.get(sessionId)?.setEffort(effort);
  }
}
