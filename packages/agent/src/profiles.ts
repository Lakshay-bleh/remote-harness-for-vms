import { existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import type { ClaudeAccount } from '@remote-harness/shared';

export type ClaudeProfile = ClaudeAccount & {
  configDir?: string; // undefined means "use whatever is already logged in on this machine"
};

const DEFAULT_PROFILE: ClaudeProfile = { id: 'default', label: 'default', configDir: undefined };

export function discoverProfiles(profilesDir: string): ClaudeProfile[] {
  if (!existsSync(profilesDir)) return [DEFAULT_PROFILE];
  // statSync follows symlinks, so a profile entry may be a real directory or
  // a symlink to an existing config dir elsewhere (e.g. one you already use
  // via a shell alias like `claude1='CLAUDE_CONFIG_DIR=~/.claude-account-1 claude'`).
  const dirs = readdirSync(profilesDir)
    .filter((name) => {
      try {
        return statSync(join(profilesDir, name)).isDirectory();
      } catch {
        return false;
      }
    })
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (dirs.length === 0) return [DEFAULT_PROFILE];
  return dirs.map((id) => ({ id, label: id, configDir: join(profilesDir, id) }));
}
