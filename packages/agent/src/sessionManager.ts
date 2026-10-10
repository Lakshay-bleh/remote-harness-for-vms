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
import { PartialText } from './partialText.js';
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
  /** The mode the chat is in now (after effectiveMode). In bypass, canUseTool answers everything itself. */
  mode: PermissionMode;
  /** Launched with the SDK's bypass opt-in, so it can be switched to bypass while running. */
  canBypass: boolean;
  /** Messages sent in whose turn has not ended yet (0 = between turns). */
  pending: number;
  /** Switched to bypass while running without the opt-in: the run is closed after its turn and resumed in bypass. */
  restartForBypass: boolean;
  closedForRestart?: boolean;
  appliedMcp: string; // the MCP config this session was last given, so an unchanged re-push is a no-op
};

/** Claude Code will not run in bypass mode as root (it exits), so there the agent itself says yes to everything instead. */
const runningAsRoot = (): boolean => typeof process.getuid === 'function' && process.getuid() === 0;

const modeLabel = (mode: PermissionMode): string => (mode === 'auto' ? 'Autonomous' : mode === 'bypassPermissions' ? 'Bypass permissions' : mode);

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

export function titleFrom(text: string): string {
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
  /** Called after each turn of a session this agent runs, and when it stops (TerminalSessionSync records where its transcript ends). */
  onTurnEnded: ((sessionId: string, cwd: string) => void) | null = null;

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
      /**
       * The mode a chat starts in when nothing was chosen for it (DEFAULT_PERMISSION_MODE, set from the owner's plan at
       * install). 'bypassPermissions' is a machine that does everything itself: its chats never wait for the phone, and the
       * app's "Autonomous" means bypass there too.
       */
      defaultMode?: PermissionMode;
      /** Injectable for tests; otherwise whether this process runs as root. */
      isRoot?: boolean;
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

  get sessionRegistry(): SessionRegistry {
    return this.registry;
  }

  isLive(sessionId: string): boolean {
    return this.live.has(sessionId);
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
      live.pending++;
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

  private get isRoot(): boolean {
    return this.opts.isRoot ?? runningAsRoot();
  }

  /**
   * On a machine set to do everything itself, the app's "Autonomous" ('auto') runs as bypass too. Handed to Claude Code as
   * is, 'auto' is its own classifier mode, which refuses some commands and then asks the person to run them by hand.
   */
  private effectiveMode(mode: PermissionMode): PermissionMode {
    return mode === 'auto' && this.opts.defaultMode === 'bypassPermissions' ? 'bypassPermissions' : mode;
  }

  /** The mode Claude Code itself runs in: as root, bypass is answered by canUseTool instead (see runningAsRoot). */
  private sdkMode(mode: PermissionMode): PermissionMode {
    return mode === 'bypassPermissions' && this.isRoot ? 'default' : mode;
  }

  private startSession(input: HubUserInput): void {
    const tempId = input.tempId;
    const existingEntry = this.registry.get(input.sessionId);
    const isResume = Boolean(existingEntry) && !tempId;
    const cwd = this.resolveCwd(input.cwd ?? existingEntry?.cwd);
    const profile = this.resolveProfile(isResume ? existingEntry?.accountId : input.accountId);

    let resolvedSessionId = isResume ? input.sessionId : '';
    const queue = new AsyncMessageQueue<SDKUserMessage>();
    // What this chat runs with: what came with the message, else what was last chosen for it here, else the defaults
    // (the machine's own default mode included).
    const choices = {
      permissionMode: input.permissionMode ?? existingEntry?.permissionMode,
      model: input.model !== undefined ? input.model : existingEntry?.model,
      effort: input.effort !== undefined ? input.effort : existingEntry?.effort,
    };
    // The run starts in the chosen mode. Bypass is only possible with the SDK's explicit opt-in at start (Claude Code refuses
    // a later switch to it in a run launched without it), so the opt-in is passed when bypass is the chosen mode, or when
    // the machine's owner made bypass this machine's default. Never as root, where Claude Code refuses it outright.
    const startMode = this.effectiveMode(choices.permissionMode ?? this.opts.defaultMode ?? 'default');
    const canBypass = !this.isRoot && (startMode === 'bypassPermissions' || this.opts.defaultMode === 'bypassPermissions');
    let session!: LiveSession;
    const options: Options = {
      cwd,
      permissionMode: this.sdkMode(startMode),
      ...(canBypass ? { allowDangerouslySkipPermissions: true } : {}),
      ...(choices.effort ? { effort: choices.effort } : {}),
      // Ask for summarized thinking so the web UI can show it like the CLI's transcript view.
      thinking: { type: 'adaptive', display: 'summarized' },
      // Stream the reply as it is written, so the phone shows it live instead of all at once at the end (see PartialText).
      includePartialMessages: true,
      // Session config is built from the *current* managed set, so a chat opened after the hub
      // changed it gets the change with no restart.
      mcpServers: this.sdkMcpConfig(),
      // Only the servers above. Without this the CLI also loads a project's own .mcp.json, and a repo that declares a server
      // called "escanor" would inherit the approvals meant for the real one (approval is decided by name).
      strictMcpConfig: true,
      canUseTool: async (toolName, toolInput, opts) => {
        if (this.isAutoAllowedMcpTool(toolName, toolInput)) return { behavior: 'allow' as const, updatedInput: toolInput };
        // Bypass: the person chose no limits, so nothing waits for the phone. What still reaches here (a question for the
        // person, or anything at all when running as root) is answered on the spot.
        if (session?.mode === 'bypassPermissions') {
          if (toolName === 'AskUserQuestion') {
            return { behavior: 'deny' as const, message: 'Nobody is watching this chat to answer. Do not ask: decide yourself and carry on.' };
          }
          return { behavior: 'allow' as const, updatedInput: toolInput };
        }
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
    session = {
      queue,
      cwd,
      mode: startMode,
      canBypass,
      pending: 1,
      restartForBypass: false,
      interrupt: () => q.interrupt(),
      setPermissionMode: (mode) => q.setPermissionMode(this.sdkMode(mode)),
      setModel: (model) => q.setModel(model),
      setEffort: (effort) => q.applyFlagSettings({ effortLevel: effort }),
      setMcpServers: (servers) => q.setMcpServers(servers),
      mcpServerStatus: () => q.mcpServerStatus(),
      close: () => q.close(),
      appliedMcp: JSON.stringify(options.mcpServers ?? {}),
    };
    this.live.set(liveKey, session);
    // A model id this Claude Code does not know must not stop the chat from starting: it is switched to once running, and a
    // refusal shows on the chat (see control()).
    if (choices.model) this.control(liveKey, 'Switching the model', (live) => live.setModel(choices.model || undefined));
    if (isResume) this.remember(input.sessionId, choices);
    else this.pendingChoices.set(liveKey, choices);

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
    const partial = new PartialText((text) =>
      this.send({ type: 'sdk_partial', sessionId: ctx.getSessionId() || ctx.tempId || ctx.liveKey, tempId: ctx.tempId, text }),
    );
    try {
      for await (const message of q) {
        if ((message as { type?: string }).type === 'stream_event') {
          partial.feed(message as Parameters<PartialText['feed']>[0]);
          continue;
        }
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
          this.registry.upsert({ sessionId, cwd: ctx.cwd, title, createdAt: new Date().toISOString(), accountId: ctx.accountId, ...definedOnly(this.pendingChoices.get(ctx.liveKey)) });
          this.pendingChoices.delete(ctx.liveKey);
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
        if (msg.type === 'assistant' || msg.type === 'result') partial.reset();
        this.send({
          type: 'sdk_message',
          sessionId: ctx.getSessionId() || ctx.tempId || ctx.liveKey,
          tempId: ctx.tempId,
          message,
        });
        if (msg.type === 'result') {
          ctx.session.pending = Math.max(0, ctx.session.pending - 1);
          if (ctx.getSessionId()) this.onTurnEnded?.(ctx.getSessionId(), ctx.cwd);
          if (ctx.session.restartForBypass && ctx.session.pending === 0 && ctx.getSessionId()) this.closeForRestart(ctx.session);
        }
      }
    } catch (err) {
      // A run closed on purpose (to restart it in bypass) has nothing to report.
      if (!ctx.session.closedForRestart) this.send({
        type: 'error',
        sessionId: ctx.getSessionId() || undefined,
        tempId: ctx.tempId,
        message: err instanceof Error ? err.message : String(err),
      });
    } finally {
      partial.reset();
      const sessionId = ctx.getSessionId();
      // A chat closed to restart in bypass may already be running again under the same id: leave that run alone.
      const replaced = Boolean(sessionId) && this.live.has(sessionId) && this.live.get(sessionId) !== ctx.session;
      // Cards still waiting for an answer belong to a session that no longer exists: deny them and drop the entries.
      if (!replaced) for (const key of new Set([sessionId, ctx.tempId, ctx.liveKey])) if (key) this.permissions.dropSession(key);
      for (const key of new Set([ctx.liveKey, sessionId])) if (key && this.live.get(key) === ctx.session) this.live.delete(key);
      this.pendingChoices.delete(ctx.liveKey);
      this.mcpSessionStatus.delete(ctx.session);
      this.reportMcpStatus();
      if (!replaced) {
        this.send({ type: 'session_ended', sessionId: sessionId || ctx.tempId || ctx.liveKey });
        if (sessionId) this.onTurnEnded?.(sessionId, ctx.cwd);
      }
    }
  }

  resolvePermission(requestId: string, behavior: PermissionDecision, message?: string): void {
    this.permissions.resolve(requestId, behavior, message);
  }

  interrupt(sessionId: string): void {
    this.control(sessionId, 'Stop', async (live) => {
      await live.interrupt();
      // Stopped: nothing is running now, so a switch to bypass that was waiting for the turn to end happens now.
      live.pending = 0;
      if (live.restartForBypass && this.live.get(sessionId) === live) this.closeForRestart(live);
    });
  }

  // A change is remembered for the chat even when it is not running, so the next message resumes it with that change
  // (it used to be dropped, and a resumed chat ran with the defaults whatever the phone showed).
  setPermissionMode(sessionId: string, requested: PermissionMode): void {
    this.remember(sessionId, { permissionMode: requested });
    const live = this.live.get(sessionId);
    if (!live) return;
    const mode = this.effectiveMode(requested);
    if (mode === 'bypassPermissions' && !live.canBypass && !this.isRoot) {
      // Claude Code refuses a switch to bypass in a run launched without the opt-in. The mode is remembered, so the run is
      // closed once it is between turns and the next message resumes it in bypass. Said once per run, not on every message.
      if (!live.restartForBypass) {
        live.restartForBypass = true;
        this.send({ type: 'error', sessionId, message: `This chat switches to ${modeLabel(requested)} the next time it starts.` });
      }
      if (live.pending === 0) this.closeForRestart(live);
      return;
    }
    live.restartForBypass = false;
    live.mode = mode;
    this.control(sessionId, 'Changing the permission mode', (l) => l.setPermissionMode(mode));
  }

  /** End a run that is between turns so its next message resumes it (in the mode now remembered for it). */
  private closeForRestart(session: LiveSession): void {
    for (const [key, s] of this.live) if (s === session) this.live.delete(key);
    session.closedForRestart = true;
    try {
      session.close();
    } catch {
      // already gone
    }
  }

  setModel(sessionId: string, model: string | undefined): void {
    this.remember(sessionId, { model: model ?? '' });
    this.control(sessionId, 'Switching the model', (live) => live.setModel(model));
  }

  setEffort(sessionId: string, effort: EffortLevel | null): void {
    this.remember(sessionId, { effort });
    this.control(sessionId, 'Changing the effort', (live) => live.setEffort(effort));
  }

  /** Mode, model and effort a new chat started with, until Claude names it (then they go into the registry). */
  private pendingChoices = new Map<string, SessionChoices>();

  private remember(sessionId: string, choices: SessionChoices): void {
    const pending = this.pendingChoices.get(sessionId);
    if (pending) {
      this.pendingChoices.set(sessionId, { ...pending, ...definedOnly(choices) });
      return;
    }
    this.registry.update(sessionId, definedOnly(choices));
  }

  // The SDK rejects control requests it can't honour (e.g. a model id its catalog doesn't know). Left unhandled, that
  // rejection kills the whole agent and every session on it, so report it on the session instead.
  private control(sessionId: string, what: string, run: (live: LiveSession) => Promise<unknown>): void {
    const live = this.live.get(sessionId);
    if (!live) return;
    run(live).catch((err) => {
      this.send({ type: 'error', sessionId, message: `${what} failed: ${err instanceof Error ? err.message : String(err)}` });
    });
  }
}

type SessionChoices = { permissionMode?: PermissionMode; model?: string; effort?: EffortLevel | null };

function definedOnly(c: SessionChoices | undefined): SessionChoices {
  const out: SessionChoices = {};
  if (!c) return out;
  if (c.permissionMode !== undefined) out.permissionMode = c.permissionMode;
  if (c.model !== undefined) out.model = c.model;
  if (c.effort !== undefined) out.effort = c.effort;
  return out;
}
