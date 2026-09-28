import { hostname } from 'node:os';
import { resolve } from 'node:path';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

export const config = {
  hubUrl: required('HUB_URL'),
  hubToken: required('HUB_TOKEN'),
  vmName: process.env.VM_NAME?.trim() || hostname(),
  workspaceRoot: resolve(process.env.WORKSPACE_ROOT || process.env.HOME || '/'),
  dataDir: resolve(process.env.DATA_DIR || './data'),
  profilesDir: resolve(process.env.PROFILES_DIR || `${process.env.HOME}/.claude-profiles`),
};
