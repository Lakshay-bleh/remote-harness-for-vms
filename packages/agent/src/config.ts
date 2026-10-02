import { homedir, hostname } from 'node:os';
import { resolve } from 'node:path';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

import { workspaceRootFrom } from './paths.js';

const workspaceRoot = workspaceRootFrom(process.env);

export const config = {
  hubUrl: required('HUB_URL'),
  hubToken: required('HUB_TOKEN'),
  vmName: process.env.VM_NAME?.trim() || hostname(),
  workspaceRoot,
  // Where the "new chat" project picker looks for subfolders. Defaults to
  // the workspace root itself, but can be narrower (e.g. everything lives
  // under WORKSPACE_ROOT but your actual projects are under ~/projects).
  projectsRoot: resolve(process.env.PROJECTS_ROOT || workspaceRoot),
  dataDir: resolve(process.env.DATA_DIR || './data'),
  profilesDir: resolve(process.env.PROFILES_DIR || `${homedir()}/.claude-profiles`),
};
