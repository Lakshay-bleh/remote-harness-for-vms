import { randomUUID } from 'node:crypto';
import { Router, type Request, type Response, type NextFunction } from 'express';
import { parseMcpServerInput, toMcpServerDto, type ImageAttachment, type McpOverviewDto, type McpPutResultDto } from '@remote-harness/shared';
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

export function createApiRouter(db: Db, agentServer: AgentServer, browserServer: BrowserServer, appPassword: string) {
  const router = Router();

  router.post('/login', (req: Request, res: Response) => {
    const { password } = req.body ?? {};
    if (password !== appPassword) {
      res.status(401).json({ error: 'Invalid password' });
      return;
    }
    res.json({ token: db.createAuthToken() });
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

  router.get('/vms', (_req, res) => {
    const vms = db.listVms().map((v) => ({ ...v, connected: agentServer.isConnected(v.id) }));
    res.json(vms);
  });

  // ---- MCP servers installed on every VM ----
  //
  // Declarative and hub-owned: whatever is stored here is pushed to every agent when it
  // connects and whenever it changes, so a VM that was offline or is brand new converges on
  // its own. Header values (credentials) go in but are never returned.

  const pushMcpServers = () => {
    const servers = db.listMcpServers();
    let delivered = 0;
    for (const vmId of agentServer.connectedVmIds()) {
      if (agentServer.sendToVm(vmId, { type: 'set_mcp_servers', servers })) delivered++;
    }
    return delivered;
  };

  router.get('/mcp-servers', (_req, res) => {
    const overview: McpOverviewDto = {
      servers: db.listMcpServers().map(toMcpServerDto),
      vms: db.listVms().map((v) => {
        const status = db.getVmMcpStatus(v.id);
        return {
          vmId: v.id,
          name: v.name,
          connected: agentServer.isConnected(v.id),
          reportedAt: status?.reportedAt ?? null,
          servers: status?.servers ?? [],
          liveSessions: status?.liveSessions ?? 0,
        };
      }),
    };
    res.json(overview);
  });

  router.put('/mcp-servers/:name', (req, res) => {
    const parsed = parseMcpServerInput(req.params.name, req.body);
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    const server = db.putMcpServer(parsed.server);
    pushMcpServers();
    const vms = db.listVms();
    const result: McpPutResultDto = {
      server: toMcpServerDto(server),
      vmsConnected: vms.filter((v) => agentServer.isConnected(v.id)).length,
      vmsTotal: vms.length,
    };
    res.json(result);
  });

  router.delete('/mcp-servers/:name', (req, res) => {
    const removed = db.deleteMcpServer(req.params.name);
    if (removed) pushMcpServers();
    res.status(removed ? 200 : 404).json({ ok: removed });
  });

  router.get('/vms/:vmId/sessions', (req, res) => {
    res.json(db.listSessionsByVm(req.params.vmId));
  });

  router.get('/vms/:vmId/projects', async (req, res) => {
    res.json(await agentServer.requestProjects(req.params.vmId));
  });

  router.get('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    res.json(db.listMessages(req.params.sessionId));
  });

  router.post('/vms/:vmId/sessions', (req, res) => {
    const { vmId } = req.params;
    const { cwd, text, images, accountId } = req.body ?? {};
    if (!text && !(images?.length > 0)) {
      res.status(400).json({ error: 'text or images required' });
      return;
    }
    const tempId = randomUUID();
    const localMessage = {
      type: 'user',
      local: true,
      message: { role: 'user', content: contentBlocks(text ?? '', images) },
    };
    db.insertMessage({ sessionId: tempId, vmId, message: localMessage });
    browserServer.broadcast({
      type: 'sdk_message',
      vmId,
      sessionId: tempId,
      message: localMessage,
      createdAt: new Date().toISOString(),
    });

    const delivered = agentServer.sendToVm(vmId, {
      type: 'user_input',
      sessionId: tempId,
      tempId,
      cwd,
      accountId,
      text: text ?? '',
      images,
    });
    if (!delivered) {
      res.status(503).json({ error: 'VM not connected' });
      return;
    }
    res.status(202).json({ tempId });
  });

  router.post('/vms/:vmId/sessions/:sessionId/messages', (req, res) => {
    const { vmId, sessionId } = req.params;
    const { text, images } = req.body ?? {};
    if (!text && !(images?.length > 0)) {
      res.status(400).json({ error: 'text or images required' });
      return;
    }
    const localMessage = {
      type: 'user',
      local: true,
      message: { role: 'user', content: contentBlocks(text ?? '', images) },
    };
    db.insertMessage({ sessionId, vmId, message: localMessage });
    db.touchSession(sessionId, 'active');
    browserServer.broadcast({
      type: 'sdk_message',
      vmId,
      sessionId,
      message: localMessage,
      createdAt: new Date().toISOString(),
    });

    const delivered = agentServer.sendToVm(vmId, { type: 'user_input', sessionId, text: text ?? '', images });
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
    const { model } = req.body ?? {};
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_model',
      sessionId: req.params.sessionId,
      model: model || undefined,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/effort', (req, res) => {
    const { effort } = req.body ?? {};
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_effort',
      sessionId: req.params.sessionId,
      effort: effort || null,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/permission-mode', (req, res) => {
    const { mode } = req.body ?? {};
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'set_permission_mode',
      sessionId: req.params.sessionId,
      mode,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  router.post('/vms/:vmId/sessions/:sessionId/permission-response', (req, res) => {
    const { requestId, behavior, message } = req.body ?? {};
    const delivered = agentServer.sendToVm(req.params.vmId, {
      type: 'permission_response',
      requestId,
      behavior,
      message,
    });
    browserServer.broadcast({
      type: 'permission_resolved',
      vmId: req.params.vmId,
      sessionId: req.params.sessionId,
      requestId,
    });
    res.status(delivered ? 202 : 503).json({ ok: delivered });
  });

  return router;
}
