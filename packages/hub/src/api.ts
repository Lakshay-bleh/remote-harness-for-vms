import { randomUUID } from 'node:crypto';
import express, { Router, type Request, type Response, type NextFunction } from 'express';
import type { ImageAttachment } from '@remote-harness/shared';
import {
  RateLimiter,
  clampLimit,
  isEffortLevel,
  isIdString,
  isPermissionBehavior,
  isPermissionMode,
  parseNewSession,
  parseUserInput,
  safeEqual,
  validateMcpUrl,
} from '@remote-harness/shared/validate';
import { securityHeaders } from './headers.js';
import type { Db } from './db.js';
import type { AgentServer } from './agentServer.js';
import type { BrowserServer } from './browserServer.js';

function contentBlocks(text: string, images: ImageAttachment[] | undefined) {
  const blocks: Record<string, unknown>[] = [];
  if (text) blocks.push({ type: 'text', text });
  for (const img of images ?? []) {
    blocks.push({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.dataBase64 } });
  }
  return blocks;
}

export type ApiOptions = {
  escanorApiUrl: string;
  allowedEmails: string[];
  // Honour X-Forwarded-For when keying the login limiter (only behind a proxy you control).
  trustProxy?: boolean;
  // Permit loopback/private MCP URLs (dev setups). Link-local / metadata addresses are always refused.
  allowPrivateMcp?: boolean;
  loginLimiter?: RateLimiter;
};

const MAX_BODY_UNAUTHENTICATED = '16kb';
const MAX_BODY_AUTHENTICATED = '20mb';
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const DEFAULT_MESSAGE_LIMIT = 2000;
const MAX_MESSAGE_LIMIT = 10_000;

export function createApiRouter(db: Db, agentServer: AgentServer, browserServer: BrowserServer, appPassword: string,
  escanor: ApiOptions,
) {
  const router = Router();
  const loginLimiter = escanor.loginLimiter ?? new RateLimiter({ maxFailures: 10, windowMs: LOGIN_WINDOW_MS });
  router.use(securityHeaders);
  router.use((_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  });

  function clientKey(req: Request): string {
    if (escanor.trustProxy) {
      const xff = req.header('x-forwarded-for');
      const first = xff?.split(',')[0]?.trim();
      if (first) return first;
    }
    return req.socket.remoteAddress ?? 'unknown';
  }

  // Pre-auth endpoints only ever need tiny bodies; the 20 MB parser sits behind requireAuth.
  router.use(['/login', '/login/escanor'], express.json({ limit: MAX_BODY_UNAUTHENTICATED }));

  function guardLogin(req: Request, res: Response): string | null {
    const key = clientKey(req);
    if (loginLimiter.blocked(key)) {
      res.setHeader('Retry-After', String(Math.ceil(LOGIN_WINDOW_MS / 1000)));
      res.status(429).json({ error: 'Too many failed sign-in attempts. Try again later.' });
      return null;
    }
    return key;
  }

  router.post('/login', (req: Request, res: Response) => {
    const key = guardLogin(req, res);
    if (!key) return;
    const { password } = req.body ?? {};
    if (!safeEqual(password, appPassword)) {
      loginLimiter.fail(key);
      res.status(401).json({ error: 'Invalid password' });
      return;
    }
    loginLimiter.succeed(key);
    res.json({ token: db.createAuthToken() });
  });

  router.post('/login/escanor', async (req: Request, res: Response) => {
    const key = guardLogin(req, res);
    if (!key) return;
    const accessToken = String(req.body?.accessToken ?? '');
    if (!accessToken) {
      res.status(400).json({ error: 'accessToken required' });
      return;
    }
    let session: any;
    try {
      const r = await fetch(`${escanor.escanorApiUrl}/auth/session`, {
        headers: { authorization: `Bearer ${accessToken}` },
        signal: AbortSignal.timeout(10_000),
      });
      if (!r.ok) {
        loginLimiter.fail(key);
        res.status(401).json({ error: 'Escanor rejected the token' });
        return;
      }
      session = await r.json();
    } catch {
      res.status(502).json({ error: 'Could not reach Escanor to verify the token' });
      return;
    }
    const u = session?.user;
    if (!u?.id || !u?.email) {
      res.status(502).json({ error: 'Unexpected Escanor session response' });
      return;
    }
    const hubUser = db.upsertHubUser({ id: String(u.id), email: String(u.email), name: u.name ?? null }, escanor.allowedEmails);
    if (!hubUser) {
      res.status(403).json({ error: 'This hub already belongs to another account' });
      return;
    }
    res.json({ token: db.createAuthToken(), hubId: hubUser.hubId });
  });

  function requireAuth(req: Request, res: Response, next: NextFunction): void {
    const header = req.header('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!db.isValidToken(token)) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    next();
  }

  router.use(requireAuth);
  router.use(express.json({ limit: MAX_BODY_AUTHENTICATED }));

  router.post('/logout', (req, res) => {
    db.revokeAuthToken((req.header('authorization') ?? '').slice(7));
    browserServer.closeRevokedSessions();
    res.status(204).end();
  });

  router.get('/mcp', (_req, res) => {
    res.json({ servers: db.listMcpServers().map((s) => ({ name: s.name, url: s.url })) });
  });

  router.post('/mcp/escanor', (req, res) => {
    const { url, token } = req.body ?? {};
    if (typeof token !== 'string' || !token || token.length > 4096) {
      res.status(400).json({ error: 'url and token required' });
      return;
    }
    const checked = validateMcpUrl(url, { allowPrivate: escanor.allowPrivateMcp });
    if (!checked.ok) {
      res.status(400).json({ error: checked.error });
      return;
    }
    db.setMcpServer('escanor', checked.value, token);
    res.json({ ok: true });
  });

  router.delete('/mcp/escanor', (_req, res) => {
    db.removeMcpServer('escanor');
    res.json({ ok: true });
  });

  router.get('/vms', (_req, res) => {
    const vms = db.listVms().map((v) => ({ ...v, connected: agentServer.isConnected(v.id) }));
    res.json(vms);
  });

  router.get('/vms/:vmId/sessions', (req, res) => {
    res.json(db.listSessionsByVm(req.params.vmId));
  });

  router.get('/vms/:vmId/projects', async (req, res) => {
    res.json(await agentServer.requestProjects(req.params.vmId));
  });

  router.get('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    const limit = clampLimit(req.query.limit, DEFAULT_MESSAGE_LIMIT, MAX_MESSAGE_LIMIT);
    res.json(db.listMessages(req.params.sessionId, req.params.vmId, limit));
  });

  function localMessage(text: string, images: ImageAttachment[] | undefined) {
    return { type: 'user', local: true, message: { role: 'user', content: contentBlocks(text, images) } };
  }

  // Refuse before storing or broadcasting anything: otherwise a request to an offline VM leaves a
  // ghost message in history that was never delivered.
  function requireConnected(vmId: string, res: Response): boolean {
    if (agentServer.isConnected(vmId)) return true;
    res.status(503).json({ error: 'VM not connected' });
    return false;
  }

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
    const message = localMessage(text, images);
    db.insertMessage({ sessionId: tempId, vmId, message });
    browserServer.broadcast({ type: 'sdk_message', vmId, sessionId: tempId, message, createdAt: new Date().toISOString() });

    const delivered = agentServer.sendToVm(vmId, { type: 'user_input', sessionId: tempId, tempId, cwd, accountId, text, images });
    if (!delivered) {
      res.status(503).json({ error: 'VM not connected' });
      return;
    }
    res.status(202).json({ tempId });
  });

  router.post('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    const { vmId, sessionId } = req.params;
    const parsed = parseUserInput(req.body);
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    if (!requireConnected(vmId, res)) return;
    const { text, images } = parsed.value;
    const message = localMessage(text, images);
    db.insertMessage({ sessionId, vmId, message });
    db.touchSession(sessionId, 'active', vmId);
    browserServer.broadcast({ type: 'sdk_message', vmId, sessionId, message, createdAt: new Date().toISOString() });

    const delivered = agentServer.sendToVm(vmId, { type: 'user_input', sessionId, text, images });
    if (!delivered) {
      res.status(503).json({ error: 'VM not connected' });
      return;
    }
    res.status(202).json({ ok: true });
  });

  router.post('/vms/:vmId/sessions/:sessionId/interrupt', (req, res) => {
    const delivered = agentServer.sendToVm(req.params.vmId, { type: 'interrupt', sessionId: req.params.sessionId });
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
      sessionId: req.params.sessionId,
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
      sessionId: req.params.sessionId,
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
      sessionId: req.params.sessionId,
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
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'permission_response',
      requestId,
      behavior,
      message,
    });
    // Only tell the UI the card is resolved if the agent actually received the answer; otherwise the
    // user would see "approved" while the agent is still blocked waiting.
    if (delivered) {
      browserServer.broadcast({
        type: 'permission_resolved',
        vmId: req.params.vmId,
        sessionId: req.params.sessionId,
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
