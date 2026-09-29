import { timingSafeEqual } from 'node:crypto';
import { Router, type NextFunction, type Request, type Response } from 'express';
import type { Db } from './db.js';
import type { AgentServer } from './agentServer.js';
import type { BrowserServer } from './browserServer.js';

// The multi-tenant control plane. It exists only when HUB_ADMIN_TOKEN is set, and only the operator
// (in practice: Escanor's backend) holds that token. Everything a tenant can do is under /api with its
// own tokens; nothing here is reachable with one.
export function createAdminRouter(db: Db, agentServer: AgentServer, browserServer: BrowserServer, adminToken: string) {
  const router = Router();

  router.use((req: Request, res: Response, next: NextFunction) => {
    if (!adminToken) {
      res.status(404).json({ error: 'Not found' });
      return;
    }
    const header = req.header('authorization') ?? '';
    const given = Buffer.from(header.startsWith('Bearer ') ? header.slice(7) : '');
    const expected = Buffer.from(adminToken);
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    next();
  });

  // Returns the tenant's credentials exactly once; the hub keeps only a hash of the agent token.
  router.post('/tenants', (req, res) => {
    const label = String(req.body?.label ?? '').trim().slice(0, 100) || 'tenant';
    res.status(201).json(db.createTenant(label));
  });

  router.get('/tenants', (_req, res) => res.json(db.listTenants()));

  router.delete('/tenants/:id', (req, res) => {
    agentServer.disconnectTenant(req.params.id);
    browserServer.disconnectTenant(req.params.id);
    const removed = db.deleteTenant(req.params.id);
    res.status(removed ? 200 : 404).json({ ok: removed });
  });

  router.post('/tenants/:id/rotate-agent-token', (req, res) => {
    const agentToken = db.rotateAgentToken(req.params.id);
    if (!agentToken) {
      res.status(404).json({ error: 'Unknown tenant' });
      return;
    }
    agentServer.disconnectTenant(req.params.id); // they must reconnect with the new token
    res.json({ agentToken });
  });

  return router;
}
