import { existsSync, readFileSync } from 'node:fs';
import { hostname } from 'node:os';
import type { HubToAgentMessage } from '@remote-harness/shared';

if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

const { config } = await import('./config.js');
const { SessionManager } = await import('./sessionManager.js');
const { HubConnection } = await import('./wsClient.js');
const { discoverProfiles } = await import('./profiles.js');
const { listProjects } = await import('./projects.js');
const { isBroadRoot } = await import('./paths.js');
const { TerminalSessionSync } = await import('./terminalSessions.js');

// The version lives in package.json (0.3.0 is the first release that installs hub-managed MCP servers, see MIN_MCP_AGENT_VERSION;
// 0.4.0 the first that takes a per-machine MCP entry; 0.5.0 the first that honours `autoAllowTools`), so it cannot drift from the release.
const AGENT_VERSION: string = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8')).version;

if (isBroadRoot(config.workspaceRoot, process.env.HOME)) {
  console.warn(
    `WARNING: WORKSPACE_ROOT is ${config.workspaceRoot}, which contains ~/.ssh, shell rc files and this agent's own .env. ` +
      'Point WORKSPACE_ROOT at a projects directory instead.',
  );
}

const profiles = discoverProfiles(config.profilesDir);
console.log(`Claude accounts: ${profiles.map((p) => p.id).join(', ')}`);

function readGuide(): string {
  if (!config.guideFile) return '';
  try {
    return readFileSync(config.guideFile, 'utf8').slice(0, 20_000);
  } catch {
    console.warn(`Could not read ESCANOR_GUIDE_FILE (${config.guideFile}); continuing without it.`);
    return '';
  }
}

const manager = new SessionManager(config.workspaceRoot, config.dataDir, profiles, (msg) => connection.send(msg), { managed: config.managed, guide: readGuide(), mcpOverride: config.mcpOverride, protectedPaths: config.protectedPaths, fetchAllow: config.fetchAllow });

// Claude Code sessions run in a terminal here show up in the app too.
const terminalSync = config.syncTerminalSessions
  ? new TerminalSessionSync({
      workspaceRoot: config.workspaceRoot,
      registry: manager.sessionRegistry,
      send: (msg) => connection.send(msg),
      isLive: (id) => manager.isLive(id),
      accountId: profiles[0].id,
    })
  : null;
if (terminalSync) manager.onSessionEnded = (id, cwd) => void terminalSync.markSynced(id, cwd);

const connection = new HubConnection(
  config.hubUrl,
  config.hubToken,
  (msg: HubToAgentMessage) => {
    switch (msg.type) {
      case 'user_input':
        manager.handleUserInput(msg);
        break;
      case 'interrupt':
        manager.interrupt(msg.sessionId);
        break;
      case 'set_permission_mode':
        manager.setPermissionMode(msg.sessionId, msg.mode);
        break;
      case 'set_model':
        manager.setModel(msg.sessionId, msg.model);
        break;
      case 'set_effort':
        manager.setEffort(msg.sessionId, msg.effort);
        break;
      case 'permission_response':
        manager.resolvePermission(msg.requestId, msg.behavior, msg.message);
        break;
      case 'set_mcp_servers':
        void manager.setMcpServers(msg.servers);
        break;
      case 'list_projects':
        connection.send({ type: 'projects_list', requestId: msg.requestId, projects: listProjects(config.projectsRoot) });
        break;
    }
  },
  () => {
    manager.resetMcpReport();
    connection.send({
      type: 'hello',
      agentVersion: AGENT_VERSION,
      vmName: config.vmName,
      hostname: hostname(),
      accounts: profiles.map((p) => ({ id: p.id, label: p.label })),
      sessions: manager.summaries(),
    });
    console.log(`Connected to hub as "${config.vmName}"`);
    void terminalSync?.syncOnce();
  },
);

connection.connect();
terminalSync?.start();

// systemd and containers stop a process with SIGTERM, so handle it like Ctrl-C: stop the Claude processes first.
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    terminalSync?.stop();
    manager.shutdown();
    connection.close();
    process.exit(0);
  });
}
