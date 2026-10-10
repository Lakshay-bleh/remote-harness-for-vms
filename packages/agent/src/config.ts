import { homedir, hostname } from 'node:os';
import { resolve } from 'node:path';
import { isPermissionMode, isValidMcpServerName, type ManagedMcpServer, type PermissionMode } from '@remote-harness/shared';
import { workspaceRootFrom } from './paths.js';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

// Throws rather than defaulting to "/" when neither WORKSPACE_ROOT nor HOME is set.
const workspaceRoot = workspaceRootFrom(process.env);

// Set by the Escanor worker container: this agent runs in a sandbox, so its local tools need no approval.
const managed = process.env.ESCANOR_MANAGED === '1';

/**
 * A per-machine MCP entry, given by whoever started this machine (an incident's): `{name, url, token, autoAllow?,
 * autoAllowReads?}`. It replaces the hub's entry of the same name on this machine, so a machine sent to look at one
 * incident uses the incident's own short-lived, read-only token instead of the workspace's standing, auto-allowed one.
 * The variable is removed from the environment once read, so a shell the agent starts does not inherit it.
 */
export function parseMcpOverride(raw: string | undefined): Omit<ManagedMcpServer, 'updatedAt'> | null {
  if (!raw) return null;
  try {
    const o = JSON.parse(raw) as Record<string, unknown>;
    const name = typeof o.name === 'string' ? o.name : '';
    const url = typeof o.url === 'string' ? o.url : '';
    const token = typeof o.token === 'string' ? o.token : '';
    if (!isValidMcpServerName(name) || !/^https?:\/\//.test(url) || !token) return null;
    return {
      name,
      url,
      headers: { Authorization: `Bearer ${token}` },
      // Fails closed: anything that changes something waits for a person, unless the entry explicitly says otherwise.
      autoAllow: o.autoAllow === true,
      autoAllowReads: o.autoAllowReads !== false,
      // Only a list of well-formed tool ids counts; anything else is ignored, which leaves the entry stricter.
      ...(Array.isArray(o.autoAllowTools)
        ? { autoAllowTools: o.autoAllowTools.filter((t): t is string => typeof t === 'string' && /^[a-z0-9][a-z0-9_-]{0,39}\.(?:[a-z0-9_.-]{1,80}|[a-z0-9_.-]{0,79}\*)$/.test(t)).slice(0, 120) }
        : {}),
      alwaysLoad: true,
      managedBy: 'override',
    };
  } catch {
    return null;
  }
}

const mcpOverride = parseMcpOverride(process.env.ESCANOR_MCP_OVERRIDE);
delete process.env.ESCANOR_MCP_OVERRIDE;

/**
 * The mode a chat starts in until the app picks one. 'bypassPermissions' = this machine does everything itself: chats never
 * wait for the phone to approve anything (and the app's "Autonomous" runs as bypass here). Unset or unknown = 'default'.
 */
export function defaultModeFrom(raw: string | undefined): PermissionMode {
  const v = raw?.trim();
  if (v && isPermissionMode(v)) return v;
  if (v) console.warn(`DEFAULT_PERMISSION_MODE=${v} is not a permission mode; using 'default'.`);
  return 'default';
}

export const config = {
  mcpOverride,
  defaultMode: defaultModeFrom(process.env.DEFAULT_PERMISSION_MODE),
  managed,
  // A short briefing appended to the assistant's system prompt (what it can reach and how to work).
  guideFile: process.env.ESCANOR_GUIDE_FILE?.trim() || '',
  hubUrl: required('HUB_URL'),
  hubToken: required('HUB_TOKEN'),
  vmName: process.env.VM_NAME?.trim() || hostname(),
  workspaceRoot,
  // Where the "new chat" project picker looks for subfolders. Defaults to
  // the workspace root itself, but can be narrower (e.g. everything lives
  // under WORKSPACE_ROOT but your actual projects are under ~/projects).
  projectsRoot: resolve(process.env.PROJECTS_ROOT || workspaceRoot),
  dataDir: resolve(process.env.DATA_DIR || './data'),
  // Show Claude Code sessions started in a terminal on this machine (inside WORKSPACE_ROOT) in the app. A managed
  // worker has no terminal user, so it is off there.
  syncTerminalSessions: process.env.SYNC_TERMINAL_SESSIONS ? process.env.SYNC_TERMINAL_SESSIONS !== '0' : !managed,
  profilesDir: resolve(process.env.PROFILES_DIR || `${homedir()}/.claude-profiles`),
  // In a managed worker WebFetch asks unless its host is listed here (comma separated; `*.example.com` allowed).
  fetchAllow: (process.env.ESCANOR_FETCH_ALLOW ?? '').split(',').map((h) => h.trim()).filter(Boolean),
  // The assistant may not change these on its own, even inside its workspace: this agent's code and its data
  // (planting code there is persistent execution as the agent's user).
  protectedPaths: [resolve(new URL('..', import.meta.url).pathname), resolve(process.env.DATA_DIR || './data')],
};
