import { existsSync } from 'node:fs';
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

// 0.3.0 is the first release that installs hub-managed MCP servers (see MIN_MCP_AGENT_VERSION).
const AGENT_VERSION = '0.3.0';

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
  },
);

connection.connect();

process.on('SIGINT', () => {
  manager.shutdown();
  connection.close();
  process.exit(0);
});
