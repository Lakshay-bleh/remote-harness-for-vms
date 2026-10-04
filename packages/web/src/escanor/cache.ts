/**
 * What the phone remembers between visits to a screen, so opening one shows what it showed last time at once while the fresh
 * answer loads behind it. Each entry has a time to live: younger than that it is trusted and no request is made on opening; older,
 * it is shown straight away and refreshed; past `maxAgeMs` it is not shown at all (stale facts are worse than a spinner).
 *
 * Kept in memory and in the phone's own storage. Never anything secret: lists and numbers the screens already show. It is emptied
 * when the person signs out, so the next person on this phone starts clean.
 */

const PREFIX = 'escanor.cache.v1:';
/** One entry above this is not kept in storage (a long chat history is its own store, not a cache). */
const MAX_ENTRY_CHARS = 250_000;

interface Entry<T> {
  v: T;
  at: number;
}

const memory = new Map<string, Entry<unknown>>();

function storage(): Storage | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

export interface CacheHit<T> {
  value: T;
  /** How long ago it was saved, in ms. */
  age: number;
  /** Younger than the time to live: trusted as is. */
  fresh: boolean;
}

export interface CachePolicy {
  key: string;
  /** Trusted without asking again for this long. */
  ttlMs: number;
  /** Shown while refreshing for this long; older is ignored. Default: a day. */
  maxAgeMs?: number;
}

export const SECOND = 1000;
export const MINUTE = 60 * SECOND;
export const HOUR = 60 * MINUTE;

export function readCache<T>(policy: CachePolicy, now = Date.now()): CacheHit<T> | null {
  let entry = memory.get(policy.key) as Entry<T> | undefined;
  if (!entry) {
    try {
      const raw = storage()?.getItem(PREFIX + policy.key);
      if (raw) {
        const parsed = JSON.parse(raw) as Entry<T>;
        if (parsed && typeof parsed.at === 'number' && 'v' in parsed) {
          entry = parsed;
          memory.set(policy.key, parsed);
        }
      }
    } catch {
      return null;
    }
  }
  if (!entry) return null;
  const age = now - entry.at;
  if (age < 0 || age > (policy.maxAgeMs ?? 24 * HOUR)) return null;
  return { value: entry.v, age, fresh: age < policy.ttlMs };
}

export function writeCache<T>(key: string, value: T, now = Date.now()): void {
  const entry: Entry<T> = { v: value, at: now };
  memory.set(key, entry);
  try {
    const raw = JSON.stringify(entry);
    if (raw.length <= MAX_ENTRY_CHARS) storage()?.setItem(PREFIX + key, raw);
    else storage()?.removeItem(PREFIX + key);
  } catch {
    // storage full or unavailable: the in-memory copy still serves this session
  }
}

/** Forget one entry, or every entry whose key starts with `prefix`. */
export function dropCache(prefix: string): void {
  for (const k of [...memory.keys()]) if (k.startsWith(prefix)) memory.delete(k);
  const s = storage();
  if (!s) return;
  try {
    for (let i = s.length - 1; i >= 0; i--) {
      const k = s.key(i);
      if (k && k.startsWith(PREFIX + prefix)) s.removeItem(k);
    }
  } catch {
    // nothing to do
  }
}

export const clearCache = (): void => dropCache('');
