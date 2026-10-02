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
const { securityHeaders } = await import('./headers.js');

const db = openDb(config.dataDir, { encryptionKey: config.encryptionKey ?? config.hubAgentToken });

const app = express();
app.disable('x-powered-by');
app.use(securityHeaders);
// The native Android app calls the hub cross-origin. Auth is a bearer token (no cookies),
// so allowing any origin doesn't widen what an attacker without the token can do.
app.use('/api', (req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.sendStatus(204);
    return;
  }
  next();
});

const httpServer = createServer(app);

const browserServer = createBrowserServer(db);

const agentServer = createAgentServer(db, config.hubAgentToken, {
  onHello(vmId, vmName, accounts, sessions) {
    db.setVmAccounts(vmId, accounts);
    for (const s of sessions) {
      db.upsertSession({ id: s.sessionId, vmId, cwd: s.cwd, title: s.title, status: s.status, accountId: s.accountId });
    }
  },
  onStatusChange(vmId, vmName, connected) {
    db.touchVmSeen(vmId);
    browserServer.broadcast({ type: 'vm_status', vmId, name: vmName, connected, accounts: db.getVmAccounts(vmId) });
  },
  onEvent(vmId, msg) {
    const now = new Date().toISOString();
    switch (msg.type) {
      case 'sdk_message': {
        db.insertMessage({ sessionId: msg.sessionId, vmId, message: msg.message });
        db.touchSession(msg.sessionId, 'active', vmId);
        browserServer.broadcast({
          type: 'sdk_message',
          vmId,
          sessionId: msg.sessionId,
          tempId: msg.tempId,
          message: msg.message,
          createdAt: now,
        });
        break;
      }
      case 'session_created': {
        db.rekeySession(msg.tempId, msg.sessionId, vmId);
        db.upsertSession({ id: msg.sessionId, vmId, cwd: msg.cwd, title: msg.title, status: 'active', accountId: msg.accountId });
        browserServer.broadcast({
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
      case 'session_ended': {
        db.touchSession(msg.sessionId, 'idle', vmId);
        browserServer.broadcast({ type: 'session_ended', vmId, sessionId: msg.sessionId });
        break;
      }
      case 'permission_request': {
        db.insertMessage({
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
        browserServer.broadcast({
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
        console.error(`[agent ${vmId}]`, msg.message);
        db.insertMessage({ sessionId, vmId, message: { type: 'error', message: msg.message } });
        browserServer.broadcast({
          type: 'sdk_message',
          vmId,
          sessionId,
          tempId: msg.tempId,
          message: { type: 'error', message: msg.message },
          createdAt: now,
        });
        break;
      }
    }
  },
});

app.use('/api', createApiRouter(db, agentServer, browserServer, config.appPassword, {
  escanorApiUrl: config.escanorApiUrl,
  allowedEmails: config.allowedEmails,
  trustProxy: config.trustProxy,
  allowPrivateMcp: config.allowPrivateMcp,
}));
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

// Close sockets whose session expired or was revoked even when nothing is being broadcast.
setInterval(() => browserServer.closeRevokedSessions(), 60_000).unref();

process.on('unhandledRejection', (err) => console.error('[hub] unhandled rejection:', err));

httpServer.listen(config.port, () => {
  console.log(`Hub listening on :${config.port}`);
});
