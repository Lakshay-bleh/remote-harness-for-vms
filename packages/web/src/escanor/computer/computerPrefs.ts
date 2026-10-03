import { useSyncExternalStore } from 'react';
import type { PairedComputer } from './lib/client';

/** What this phone remembers about ONE computer: a name of the person's choosing, and how to reach it. Kept on this phone only. */
export type RoutePref = 'auto' | 'cloud' | 'lan';
export interface ComputerPrefs {
  alias: string;
  route: RoutePref;
}

const DEFAULTS: ComputerPrefs = { alias: '', route: 'auto' };
const KEY = 'escanor.computer.prefs.v1';

/** A name as typed: control characters out, spaces collapsed, at most 40 characters. */
export function cleanName(raw: string): string {
  // eslint-disable-next-line no-control-regex
  return raw.replace(/[\u0000-\u001f\u007f]/g, '').replace(/\s+/g, ' ').trim().slice(0, 40);
}

export function parseComputerPrefs(raw: string | null): ComputerPrefs {
  let v: unknown = null;
  try {
    v = raw ? JSON.parse(raw) : null;
  } catch {
    v = null;
  }
  const o = v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  return {
    alias: typeof o.alias === 'string' ? cleanName(o.alias) : DEFAULTS.alias,
    route: o.route === 'cloud' || o.route === 'lan' || o.route === 'auto' ? o.route : DEFAULTS.route,
  };
}

export const displayName = (c: PairedComputer, p: ComputerPrefs): string => p.alias || c.name;

/** The computer to connect to, and whether the cloud route may be used, for a connection preference. Never changes the stored computer. */
export function applyRoute(c: PairedComputer, route: RoutePref): { computer: PairedComputer; cloud: boolean } {
  if (route === 'cloud') return { computer: { ...c, lan: [] }, cloud: true };
  if (route === 'lan') return { computer: c, cloud: false };
  return { computer: c, cloud: true };
}

// ---- storage: one small record per computer id
type All = Record<string, ComputerPrefs>;
const listeners = new Set<() => void>();
let cache: All | null = null;

function readAll(): All {
  if (cache) return cache;
  const out: All = {};
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? '{}');
    if (v && typeof v === 'object') for (const [id, p] of Object.entries(v)) out[id] = parseComputerPrefs(JSON.stringify(p));
  } catch {
    // damaged: start clean
  }
  return (cache = out);
}

export const getComputerPrefs = (id: string): ComputerPrefs => readAll()[id] ?? DEFAULTS;

export function setComputerPrefs(id: string, patch: Partial<ComputerPrefs>): void {
  const next = parseComputerPrefs(JSON.stringify({ ...getComputerPrefs(id), ...patch }));
  cache = { ...readAll(), [id]: next };
  try {
    localStorage.setItem(KEY, JSON.stringify(cache));
  } catch {
    // not saved, but it applies until the app closes
  }
  listeners.forEach((l) => l());
}

export function forgetComputerPrefs(id: string): void {
  const { [id]: _gone, ...rest } = readAll();
  cache = rest;
  try {
    localStorage.setItem(KEY, JSON.stringify(rest));
  } catch {
    // nothing to remove
  }
  listeners.forEach((l) => l());
}

export function useComputerPrefs(id: string): ComputerPrefs {
  return useSyncExternalStore(
    (cb) => (listeners.add(cb), () => void listeners.delete(cb)),
    () => getComputerPrefs(id),
    () => DEFAULTS,
  );
}
