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

const AGENT_VERSION: string = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8')).version;

if (isBroadRoot(config.workspaceRoot, process.env.HOME)) {
  console.warn(
    `WARNING: WORKSPACE_ROOT is ${config.workspaceRoot}, which contains ~/.ssh, shell rc files and this agent's own .env. ` +
      'Point WORKSPACE_ROOT at a projects directory instead.',
  );
}

const profiles = discoverProfiles(config.profilesDir);
console.log(`Claude accounts: ${profiles.map((p) => p.id).join(', ')}`);

const manager = new SessionManager(config.workspaceRoot, config.dataDir, profiles, (msg) => connection.send(msg));

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
      case 'list_projects':
        connection.send({ type: 'projects_list', requestId: msg.requestId, projects: listProjects(config.projectsRoot) });
        break;
    }
  },
  () => {
    connection.send({
      type: 'hello',
      agentVersion: AGENT_VERSION,
      vmName: config.vmName,
      hostname: hostname(),
      accounts: profiles.map((p) => ({ id: p.id, label: p.label })),
      sessions: manager.summaries(),
    });
    console.log(`Connected to hub as "${config.vmName}"`);
  },
);

connection.connect();

// systemd stops services with SIGTERM, so handle it as well as Ctrl-C.
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    connection.close();
    process.exit(0);
  });
}
