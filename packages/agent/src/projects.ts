import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const IGNORED = new Set(['.git', 'node_modules', '.claude', '.claude-profiles']);

// One level of subdirectories under the workspace root, so a VM that hosts
// several projects (e.g. ~/projects/app-a, ~/projects/app-b) can offer them
// as pickable cwds for a new chat, instead of always defaulting to the root.
export function listProjects(workspaceRoot: string): string[] {
  try {
    return readdirSync(workspaceRoot)
      .filter((name) => !name.startsWith('.') && !IGNORED.has(name))
      .filter((name) => {
        try {
          return statSync(join(workspaceRoot, name)).isDirectory();
        } catch {
          return false;
        }
      })
      .sort((a, b) => a.localeCompare(b));
  } catch {
    return [];
  }
}
