import { hostname } from 'node:os';
import { resolve } from 'node:path';
import type { ManagedMcpServer } from '@remote-harness/shared';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

const workspaceRoot = resolve(process.env.WORKSPACE_ROOT || process.env.HOME || '/');

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
    if (!/^[a-z0-9][a-z0-9_-]{0,31}$/.test(name) || !/^https?:\/\//.test(url) || !token) return null;
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

export const config = {
  mcpOverride,
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
  profilesDir: resolve(process.env.PROFILES_DIR || `${process.env.HOME}/.claude-profiles`),
};
