import { randomUUID } from 'node:crypto';
import express, { Router, type Request, type Response, type NextFunction } from 'express';
import { agentSupportsMcp, parseMcpServerInput, toMcpServerDto, type ApiTokenCreatedDto, type ApiTokenScope, type ImageAttachment, type McpOverviewDto, type McpPutResultDto } from '@remote-harness/shared';
import {
  RateLimiter,
  clampLimit,
  isEffortLevel,
  isIdString,
  isPermissionBehavior,
  isPermissionMode,
  parseNewSession,
  parseRunChoices,
  parseUserInput,
  safeEqual,
} from '@remote-harness/shared/validate';
import { DEFAULT_MESSAGE_LIMIT, DEFAULT_TENANT, type Db } from './db.js';
import type { AgentServer } from './agentServer.js';
import type { BrowserServer } from './browserServer.js';
import { securityHeaders } from './headers.js';

function contentBlocks(text: string, images: ImageAttachment[] | undefined) {
  const blocks: Record<string, unknown>[] = [];
  if (text) blocks.push({ type: 'text', text });
  for (const img of images ?? []) {
    blocks.push({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.dataBase64 } });
  }
  return blocks;
}

export type ApiOptions = {
  /** Honour X-Forwarded-For when keying the login limiter (only behind a proxy you control). */
  trustProxy?: boolean;
  /** Accept loopback / private-network MCP URLs. Metadata and link-local addresses never pass. */
  allowPrivateMcp?: boolean;
  loginMaxFailures?: number;
  loginLimiter?: RateLimiter;
};

const MAX_BODY_UNAUTHENTICATED = '16kb';
const MAX_BODY_AUTHENTICATED = '20mb';
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const MAX_MESSAGE_LIMIT = 10_000;
const DEFAULT_SEARCH_LIMIT = 20;
const MAX_SEARCH_LIMIT = 100;
const MIN_TOKEN_TTL_SECONDS = 60;
const MAX_TOKEN_TTL_SECONDS = 2 * 365 * 24 * 60 * 60;

/** `?after=` / `?before=` a message id: a whole number, else nothing (the newest messages). */
function idCursor(v: unknown): number | undefined {
  const n = typeof v === 'string' && /^\d{1,15}$/.test(v) ? Number(v) : NaN;
  return Number.isSafeInteger(n) ? n : undefined;
}

export function createApiRouter(db: Db, agentServer: AgentServer, browserServer: BrowserServer, appPassword: string, opts: ApiOptions = {}) {
  const router = Router();
  const loginLimiter = opts.loginLimiter ?? new RateLimiter({ maxFailures: opts.loginMaxFailures ?? 10, windowMs: LOGIN_WINDOW_MS });
  router.use(securityHeaders);
  router.use((_req, res, next) => { res.set({ 'Cache-Control': 'no-store' }); next(); });

  const clientKey = (req: Request): string => {
    if (opts.trustProxy) {
      const first = req.header('x-forwarded-for')?.split(',')[0]?.trim();
      if (first) return first;
    }
    return req.socket.remoteAddress ?? 'unknown';
  };

  // Pre-auth endpoints only ever need a tiny body; the 20 MB parser sits behind requireAuth.
  router.use('/login', express.json({ limit: MAX_BODY_UNAUTHENTICATED }));

  // Password login is the classic single-tenant hub's front door: it signs in to the default tenant.
  // Other tenants have no password; they hold API tokens issued by the admin API.
  router.post('/login', (req: Request, res: Response) => {
    const key = clientKey(req);
    if (loginLimiter.blocked(key)) {
      res.setHeader('Retry-After', String(LOGIN_WINDOW_MS / 1000));
      res.status(429).json({ error: 'Too many failed sign-in attempts. Try again later.' });
      return;
    }
    if (!safeEqual(req.body?.password, appPassword)) {
      loginLimiter.fail(key);
      res.status(401).json({ error: 'Invalid password' });
      return;
    }
    loginLimiter.succeed(key);
    res.json({ token: db.for(DEFAULT_TENANT).createAuthToken() });
  });

  function requireAuth(req: Request, res: Response, next: NextFunction): void {
    const header = req.header('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const cred = db.credentialForApiToken(token);
    if (cred) {
      res.locals.tenantId = cred.tenantId;
      res.locals.kind = cred.kind; // 'login' (a browser session) or 'api' (a purpose-built token)
      res.locals.scope = cred.scope;
      next();
      return;
    }
    // A token issued for one machine: it may see and drive that machine, and nothing else of the tenant's.
    const machine = db.machineForApiToken(token);
    if (!machine) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    res.locals.tenantId = machine.tenantId;
    res.locals.machine = machine;
    next();
  }

  router.use(requireAuth);
  router.use(express.json({ limit: MAX_BODY_AUTHENTICATED }));

  // A token issued for MCP management (what Escanor gets) can manage the MCP registry and nothing else: it cannot start
  // sessions, answer permission cards or change a session's permission mode. A leak of it must not be code execution.
  router.use((req, res, next) => {
    if (res.locals.scope !== 'mcp') {
      next();
      return;
    }
    if (req.path === '/mcp-servers' || req.path.startsWith('/mcp-servers/')) {
      next();
      return;
    }
    res.status(403).json({ error: 'This token is limited to managing MCP servers.' });
  });

  // What a machine-scoped token may reach: the machine list (filtered to itself), the MCP overview, and the routes under
  // its own machine. Never tokens, logout, or changes to the tenant's MCP servers.
  router.use((req, res, next) => {
    if (!res.locals.machine) {
      next();
      return;
    }
    const readOnlyOk = req.method === 'GET' && (req.path === '/vms' || req.path === '/mcp-servers');
    if (readOnlyOk || req.path.startsWith('/vms/')) {
      next();
      return;
    }
    res.status(403).json({ error: 'This credential is limited to one machine.' });
  });

  // Everything below acts for the caller's tenant only.
  const T = (res: Response) => db.for(res.locals.tenantId as string);
  const tenantOf = (res: Response) => res.locals.tenantId as string;

  // A VM id in a URL must be one of the caller's. Without this, knowing (or guessing) another tenant's
  // VM id would be enough to message its machine, since sockets are looked up by VM id alone.
  router.param('vmId', (_req, res, next, vmId) => {
    const own = T(res).listVms().find((v) => v.id === vmId);
    // A machine-scoped token reaches its own machine only; another one of the tenant's looks like it does not exist.
    if (!own || (res.locals.machine && own.name !== (res.locals.machine as { vmName: string }).vmName)) {
      res.status(404).json({ error: 'Unknown VM' });
      return;
    }
    next();
  });

  // ---- tokens ----
  // Signing out really signs out: the token is deleted, so a copy of it stops working too.
  router.post('/logout', (req, res) => {
    const header = req.header('authorization') ?? '';
    T(res).revokeToken(header.startsWith('Bearer ') ? header.slice(7) : '');
    browserServer.closeRevokedSessions();
    res.json({ ok: true });
  });

  // A token for one purpose, e.g. Escanor. Unlike a login it survives signing out, and it can be revoked on its own. The value
  // is returned once and never listed again. Only a signed-in browser session can mint one: a token that could mint more
  // would let a leaked integration token keep itself alive forever. It expires, and `scope: "mcp"` limits it to the MCP registry.
  router.post('/tokens', (req, res) => {
    if (res.locals.kind !== 'login') {
      res.status(403).json({ error: 'Only a signed-in session can create tokens.' });
      return;
    }
    const label = String(req.body?.label ?? '').trim().slice(0, 60) || 'API token';
    const scope = req.body?.scope ?? 'full';
    if (scope !== 'full' && scope !== 'mcp') {
      res.status(400).json({ error: 'scope must be "full" or "mcp"' });
      return;
    }
    const ttl = req.body?.ttlSeconds;
    if (ttl !== undefined && (typeof ttl !== 'number' || !Number.isFinite(ttl) || ttl < MIN_TOKEN_TTL_SECONDS || ttl > MAX_TOKEN_TTL_SECONDS)) {
      res.status(400).json({ error: `ttlSeconds must be between ${MIN_TOKEN_TTL_SECONDS} and ${MAX_TOKEN_TTL_SECONDS}` });
      return;
    }
    const created: ApiTokenCreatedDto = T(res).createApiToken(label, { scope: scope as ApiTokenScope, ttlSeconds: ttl });
    res.status(201).json(created);
  });
  router.get('/tokens', (_req, res) => res.json(T(res).listApiTokens()));
  router.delete('/tokens/:id', (req, res) => {
    const removed = T(res).deleteApiToken(req.params.id);
    browserServer.closeRevokedSessions();
    res.status(removed ? 200 : 404).json({ ok: removed });
  });

  router.get('/vms', (_req, res) => {
    const only = (res.locals.machine as { vmName: string } | undefined)?.vmName;
    const vms = T(res)
      .listVms()
      .filter((v) => !only || v.name === only)
      .map((v) => ({ ...v, connected: agentServer.isConnected(v.id) }));
    res.json(vms);
  });

  // ---- MCP servers installed on every VM ----
  //
  // Declarative and hub-owned: whatever is stored here is pushed to every agent when it
  // connects and whenever it changes, so a VM that was offline or is brand new converges on
  // its own. Header values (credentials) go in but are never returned.

  const pushMcpServers = (tenantId: string) => {
    const servers = db.for(tenantId).listMcpServers();
    let delivered = 0;
    for (const vmId of agentServer.connectedVmIds(tenantId)) {
      if (agentServer.sendToVm(vmId, { type: 'set_mcp_servers', servers })) delivered++;
    }
    return delivered;
  };

  router.get('/mcp-servers', (_req, res) => {
    const overview: McpOverviewDto = {
      servers: T(res).listMcpServers().map(toMcpServerDto),
      vms: T(res).listVms().filter((v) => !res.locals.machine || v.name === (res.locals.machine as { vmName: string }).vmName).map((v) => {
        const status = T(res).getVmMcpStatus(v.id);
        return {
          vmId: v.id,
          name: v.name,
          connected: agentServer.isConnected(v.id),
          agentVersion: T(res).getVmAgentVersion(v.id),
          mcpSupported: agentSupportsMcp(T(res).getVmAgentVersion(v.id)),
          reportedAt: status?.reportedAt ?? null,
          servers: status?.servers ?? [],
          liveSessions: status?.liveSessions ?? 0,
        };
      }),
    };
    res.json(overview);
  });

  router.put('/mcp-servers/:name', (req, res) => {
    const existing = T(res).listMcpServers().find((s) => s.name === req.params.name);
    const parsed = parseMcpServerInput(req.params.name, req.body, { existing, allowPrivate: opts.allowPrivateMcp });
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    const server = T(res).putMcpServer(parsed.server);
    pushMcpServers(tenantOf(res));
    const vms = T(res).listVms();
    const result: McpPutResultDto = {
      server: toMcpServerDto(server),
      vmsConnected: vms.filter((v) => agentServer.isConnected(v.id)).length,
      vmsTotal: vms.length,
    };
    res.json(result);
  });

  router.delete('/mcp-servers/:name', (req, res) => {
    const removed = T(res).deleteMcpServer(req.params.name);
    if (removed) pushMcpServers(tenantOf(res));
    res.status(removed ? 200 : 404).json({ ok: removed });
  });

  router.get('/vms/:vmId/sessions', (req, res) => {
    res.json(T(res).listSessionsByVm(req.params.vmId));
  });

  // Search this VM's chats by title and by what was said in them. Declared before the `/sessions/:sessionId` routes so
  // "search" is never taken for a session id.
  router.get('/vms/:vmId/sessions/search', (req, res) => {
    const q = typeof req.query.q === 'string' ? req.query.q : '';
    const limit = clampLimit(req.query.limit, DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT);
    res.json(T(res).searchSessions(req.params.vmId, q, limit));
  });

  router.get('/vms/:vmId/projects', async (req, res) => {
    res.json(await agentServer.requestProjects(req.params.vmId));
  });

  router.get('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    const limit = clampLimit(req.query.limit, DEFAULT_MESSAGE_LIMIT, MAX_MESSAGE_LIMIT);
    res.json(T(res).listMessages(T(res).resolveSession(req.params.sessionId), limit, req.params.vmId, idCursor(req.query.after), idCursor(req.query.before)));
  });

  router.patch('/vms/:vmId/sessions/:sessionId', (req, res) => {
    const title = typeof req.body?.title === 'string' ? req.body.title.trim() : '';
    if (!title || title.length > 200) {
      res.status(400).json({ error: 'title must be 1 to 200 characters' });
      return;
    }
    const ok = T(res).renameSession(T(res).resolveSession(req.params.sessionId), req.params.vmId, title);
    res.status(ok ? 200 : 404).json(ok ? { ok: true } : { error: 'No such chat' });
  });

  router.delete('/vms/:vmId/sessions/:sessionId', (req, res) => {
    const ok = T(res).deleteSession(T(res).resolveSession(req.params.sessionId), req.params.vmId);
    res.status(ok ? 200 : 404).json(ok ? { ok: true } : { error: 'No such chat' });
  });

  const userMessage = (text: string, images: ImageAttachment[] | undefined) => ({
    type: 'user',
    local: true,
    message: { role: 'user', content: contentBlocks(text, images) },
  });

  // Refuse before storing or broadcasting anything: otherwise a request to an offline VM leaves a message in the history
  // that was never delivered.
  const requireConnected = (vmId: string, res: Response): boolean => {
    if (agentServer.isConnected(vmId)) return true;
    res.status(503).json({ error: 'VM not connected' });
    return false;
  };

  router.post('/vms/:vmId/sessions', (req, res) => {
    const { vmId } = req.params;
    const parsed = parseNewSession(req.body);
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    if (!requireConnected(vmId, res)) return;
    const { text, images, cwd, accountId } = parsed.value;
    const tempId = randomUUID();
    const localMessage = userMessage(text, images);
    T(res).insertMessage({ sessionId: tempId, vmId, message: localMessage });
    browserServer.broadcast(tenantOf(res), { type: 'sdk_message', vmId, sessionId: tempId, message: localMessage, createdAt: new Date().toISOString() });

    const delivered = agentServer.sendToVm(vmId, { type: 'user_input', sessionId: tempId, tempId, cwd, accountId, text, images, ...parseRunChoices(req.body) });
    if (!delivered) {
      res.status(503).json({ error: 'VM not connected' });
      return;
    }
    res.status(202).json({ tempId });
  });

  router.post('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    const { vmId } = req.params;
    const sessionId = T(res).resolveSession(req.params.sessionId);
    const parsed = parseUserInput(req.body);
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    if (!requireConnected(vmId, res)) return;
    const { text, images } = parsed.value;
    const localMessage = userMessage(text, images);
    T(res).insertMessage({ sessionId, vmId, message: localMessage });
    T(res).touchSession(sessionId, 'active', vmId);
    browserServer.broadcast(tenantOf(res), { type: 'sdk_message', vmId, sessionId, message: localMessage, createdAt: new Date().toISOString() });

    const delivered = agentServer.sendToVm(vmId, { type: 'user_input', sessionId, text, images, ...parseRunChoices(req.body) });
    if (!delivered) {
      res.status(503).json({ error: 'VM not connected' });
      return;
    }
    res.status(202).json({ ok: true });
  });

  router.post('/vms/:vmId/sessions/:sessionId/interrupt', (req, res) => {
    const delivered = agentServer.sendToVm(req.params.vmId, { type: 'interrupt', sessionId: T(res).resolveSession(req.params.sessionId) });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/model', (req, res) => {
    const model = req.body?.model;
    if (model !== undefined && model !== null && (typeof model !== 'string' || model.length > 200)) {
      res.status(400).json({ error: 'model must be a string' });
      return;
    }
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_model',
      sessionId: T(res).resolveSession(req.params.sessionId),
      model: model || undefined,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/effort', (req, res) => {
    const effort = req.body?.effort;
    if (effort !== undefined && effort !== null && effort !== '' && !isEffortLevel(effort)) {
      res.status(400).json({ error: 'invalid effort level' });
      return;
    }
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_effort',
      sessionId: T(res).resolveSession(req.params.sessionId),
      effort: effort || null,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/permission-mode', (req, res) => {
    const mode = req.body?.mode;
    if (!isPermissionMode(mode)) {
      res.status(400).json({ error: 'invalid permission mode' });
      return;
    }
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_permission_mode',
      sessionId: T(res).resolveSession(req.params.sessionId),
      mode,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/permission-response', (req, res) => {
    const { requestId, behavior, message } = req.body ?? {};
    if (!isIdString(requestId) || !isPermissionBehavior(behavior) || (message !== undefined && (typeof message !== 'string' || message.length > 4000))) {
      res.status(400).json({ error: 'requestId and behavior (allow|deny) required' });
      return;
    }
    const delivered = agentServer.sendToVm(req.params.vmId, { type: 'permission_response', requestId, behavior, message });
    // Only tell the UI the card is resolved if the agent actually received the answer; otherwise the user would see
    // "approved" while the agent is still blocked waiting.
    if (delivered) {
      browserServer.broadcast(tenantOf(res), {
        type: 'permission_resolved',
        vmId: req.params.vmId,
        sessionId: T(res).resolveSession(req.params.sessionId),
        requestId,
      });
    }
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  // express.json() failures (413 too large, 400 malformed) should be JSON like everything else.
  router.use((err: any, _req: Request, res: Response, next: NextFunction) => {
    if (res.headersSent) return next(err);
    const status = typeof err?.status === 'number' && err.status >= 400 && err.status < 500 ? err.status : 500;
    res.status(status).json({ error: status === 413 ? 'Request body too large' : status === 500 ? 'Internal error' : 'Bad request' });
  });

  return router;
}
