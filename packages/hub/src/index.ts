import { existsSync } from 'node:fs';
import { createServer } from 'node:http';
import express from 'express';

if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

const { config } = await import('./config.js');
const { openDb } = await import('./db.js');
const { createAgentServer } = await import('./agentServer.js');
const { createBrowserServer } = await import('./browserServer.js');
const { createApiRouter } = await import('./api.js');
const { createAdminRouter } = await import('./admin.js');

const db = openDb(config.dataDir);

const app = express();
// The native Android app calls the hub cross-origin. Auth is a bearer token (no cookies),
// so allowing any origin doesn't widen what an attacker without the token can do.
app.use(['/api', '/admin'], (req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.sendStatus(204);
    return;
  }
  next();
});
app.use(express.json({ limit: '20mb' }));

const httpServer = createServer(app);

const browserServer = createBrowserServer(db);

const agentServer = createAgentServer(db, config.hubAgentToken, {
  onHello(tenantId, vmId, vmName, accounts, sessions, agentVersion) {
    const t = db.for(tenantId);
    t.setVmAccounts(vmId, accounts);
    t.setVmAgentVersion(vmId, agentVersion);
    for (const s of sessions) {
      t.upsertSession({ id: s.sessionId, vmId, cwd: s.cwd, title: s.title, status: s.status, accountId: s.accountId });
    }
    // Every (re)connect converges the VM on the tenant's MCP servers, so a new VM, or one that was
    // offline while they changed, needs nothing done to it.
    agentServer.sendToVm(vmId, { type: 'set_mcp_servers', servers: t.listMcpServers() });
  },
  onStatusChange(tenantId, vmId, vmName, connected) {
    const t = db.for(tenantId);
    t.touchVmSeen(vmId);
    browserServer.broadcast(tenantId, { type: 'vm_status', vmId, name: vmName, connected, accounts: t.getVmAccounts(vmId) });
  },
  onEvent(tenantId, vmId, msg) {
    const t = db.for(tenantId);
    const broadcast = (m: Parameters<typeof browserServer.broadcast>[1]) => browserServer.broadcast(tenantId, m);
    const now = new Date().toISOString();
    switch (msg.type) {
      case 'sdk_message': {
        t.insertMessage({ sessionId: msg.sessionId, vmId, message: msg.message });
        t.touchSession(msg.sessionId, 'active');
        broadcast({ type: 'sdk_message', vmId, sessionId: msg.sessionId, tempId: msg.tempId, message: msg.message, createdAt: now });
        break;
      }
      case 'session_created': {
        t.rekeySession(msg.tempId, msg.sessionId);
        t.upsertSession({ id: msg.sessionId, vmId, cwd: msg.cwd, title: msg.title, status: 'active', accountId: msg.accountId });
        broadcast({
          type: 'session_created',
          vmId,
          tempId: msg.tempId,
          sessionId: msg.sessionId,
          cwd: msg.cwd,
          title: msg.title,
          accountId: msg.accountId,
        });
        break;
      }
      case 'mcp_status': {
        t.setVmMcpStatus(vmId, { servers: msg.servers, liveSessions: msg.liveSessions });
        break;
      }
      case 'session_ended': {
        t.touchSession(msg.sessionId, 'idle');
        broadcast({ type: 'session_ended', vmId, sessionId: msg.sessionId });
        break;
      }
      case 'permission_request': {
        t.insertMessage({
          sessionId: msg.sessionId,
          vmId,
          message: {
            type: 'permission_request',
            requestId: msg.requestId,
            toolName: msg.toolName,
            input: msg.input,
            blockedPath: msg.blockedPath,
          },
        });
        broadcast({
          type: 'permission_request',
          vmId,
          sessionId: msg.sessionId,
          requestId: msg.requestId,
          toolName: msg.toolName,
          input: msg.input,
          blockedPath: msg.blockedPath,
        });
        break;
      }
      case 'error': {
        const sessionId = msg.sessionId ?? msg.tempId ?? 'unknown';
        console.error(`[agent ${tenantId}/${vmId}]`, msg.message);
        t.insertMessage({ sessionId, vmId, message: { type: 'error', message: msg.message } });
        broadcast({ type: 'sdk_message', vmId, sessionId, tempId: msg.tempId, message: { type: 'error', message: msg.message }, createdAt: now });
        break;
      }
    }
  },
});

app.use('/admin', createAdminRouter(db, agentServer, browserServer, config.hubAdminToken, config.machineMinTtlSeconds));
app.use('/api', createApiRouter(db, agentServer, browserServer, config.appPassword));
app.use(express.static(config.webDist));
app.get('*', (_req, res) => {
  res.sendFile('index.html', { root: config.webDist });
});

httpServer.on('upgrade', (req, socket, head) => {
  const pathname = new URL(req.url ?? '', 'http://localhost').pathname;
  if (pathname === '/agent') {
    if (!agentServer.authorize(req)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    agentServer.wss.handleUpgrade(req, socket, head, (ws) => agentServer.wss.emit('connection', ws, req));
  } else if (pathname === '/ws') {
    if (!browserServer.authorize(req)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    browserServer.wss.handleUpgrade(req, socket, head, (ws) => browserServer.wss.emit('connection', ws, req));
  } else {
    socket.destroy();
  }
});

httpServer.listen(config.port, () => {
  console.log(`Hub listening on :${config.port}`);
});
