import { existsSync, realpathSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

export const isInside = (root: string, candidate: string): boolean => {
  const rel = relative(root, candidate);
  // "..foo" is a legal directory name; only ".." itself and "../x" escape.
  return rel === '' || (rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
};

// realpath of the deepest existing ancestor, with the not-yet-created remainder re-appended, so a
// symlink anywhere in the existing part of the path is resolved before the containment check.
export function realpathLoose(p: string): string {
  let existing = p;
  const rest: string[] = [];
  while (!existsSync(existing)) {
    const parent = dirname(existing);
    if (parent === existing) break;
    rest.unshift(basename(existing));
    existing = parent;
  }
  let real: string;
  try {
    real = realpathSync(existing);
  } catch {
    real = existing;
  }
  return rest.length ? join(real, ...rest) : real;
}

// Resolves `requested` against the workspace root and refuses anything that lands outside it once
// symlinks are followed (the model can create symlinks via Bash). Falls back to the root itself.
export function resolveInside(root: string, requested: string | undefined): string {
  const realRoot = realpathLoose(root);
  const candidate = realpathLoose(resolve(realRoot, requested || '.'));
  return isInside(realRoot, candidate) ? candidate : realRoot;
}

export function workspaceRootFrom(env: Record<string, string | undefined>): string {
  const root = env.WORKSPACE_ROOT || env.HOME;
  if (!root) throw new Error('Set WORKSPACE_ROOT (HOME is not set); refusing to default the workspace to "/"');
  return resolve(root);
}

// A workspace of "/" or the whole home directory exposes ~/.ssh, shell rc files and the agent's own
// .env as "inside the workspace".
export function isBroadRoot(root: string, home: string | undefined): boolean {
  const r = resolve(root);
  return r === '/' || (home !== undefined && home !== '' && r === resolve(home));
}
