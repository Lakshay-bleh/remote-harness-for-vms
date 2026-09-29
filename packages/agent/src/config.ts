import { hostname } from 'node:os';
import { resolve } from 'node:path';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

const workspaceRoot = resolve(process.env.WORKSPACE_ROOT || process.env.HOME || '/');

// Set by the Escanor worker container: this agent runs in a sandbox, so its local tools need no approval.
const managed = process.env.ESCANOR_MANAGED === '1';

export const config = {
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
