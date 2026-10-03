import { useSyncExternalStore } from 'react';

/**
 * How a person organises their assistant chats: pinned ones on top, their own names, an archive, and search. The server only
 * knows a chat's id, its generated title and when it was last used, so the rest is kept on this phone.
 */
export interface ChatMeta {
  pinned: string[];
  /** Names the person gave, by chat id. */
  titles: Record<string, string>;
  archived: string[];
}

export const EMPTY_META: ChatMeta = { pinned: [], titles: {}, archived: [] };

export interface ChatItem {
  id: string;
  /** What the server calls it. */
  title: string;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface ChatRow extends ChatItem {
  /** What to show: the person's own name if they gave one. */
  name: string;
  pinned: boolean;
  archived: boolean;
}

export interface ChatSection {
  key: string;
  label: string;
  rows: ChatRow[];
}

const KEY = 'escanor.chats.v1';
const strings = (v: unknown): string[] => (Array.isArray(v) ? [...new Set(v.filter((x): x is string => typeof x === 'string' && x.length > 0 && x.length < 200))] : []);

/** Read stored organisation defensively: anything damaged becomes an empty field instead of an error. */
export function parseMeta(raw: string | null): ChatMeta {
  let v: unknown = null;
  try {
    v = raw ? JSON.parse(raw) : null;
  } catch {
    v = null;
  }
  const o = v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  const titles: Record<string, string> = {};
  if (o.titles && typeof o.titles === 'object' && !Array.isArray(o.titles)) {
    for (const [id, name] of Object.entries(o.titles as Record<string, unknown>)) {
      if (typeof name === 'string' && name.trim() && name.length <= 120) titles[id] = name.trim();
    }
  }
  return { pinned: strings(o.pinned), titles, archived: strings(o.archived) };
}

/** A name for a chat: trimmed, one line, not absurdly long. Empty means "go back to the generated title". */
export function cleanName(text: string): string {
  return text.replace(/\s+/g, ' ').trim().slice(0, 80);
}

export const togglePinned = (m: ChatMeta, id: string): ChatMeta => ({ ...m, pinned: m.pinned.includes(id) ? m.pinned.filter((x) => x !== id) : [id, ...m.pinned] });
export const toggleArchived = (m: ChatMeta, id: string): ChatMeta => ({ ...m, archived: m.archived.includes(id) ? m.archived.filter((x) => x !== id) : [...m.archived, id], pinned: m.pinned.filter((x) => x !== id) });
export function rename(m: ChatMeta, id: string, text: string): ChatMeta {
  const name = cleanName(text);
  const titles = { ...m.titles };
  if (name) titles[id] = name;
  else delete titles[id];
  return { ...m, titles };
}
/** Forget everything about chats that no longer exist (deleted here or elsewhere). */
export function prune(m: ChatMeta, liveIds: string[]): ChatMeta {
  const live = new Set(liveIds);
  const titles = Object.fromEntries(Object.entries(m.titles).filter(([id]) => live.has(id)));
  const next = { pinned: m.pinned.filter((id) => live.has(id)), titles, archived: m.archived.filter((id) => live.has(id)) };
  const same = next.pinned.length === m.pinned.length && next.archived.length === m.archived.length && Object.keys(titles).length === Object.keys(m.titles).length;
  return same ? m : next;
}

const DAY = 86_400_000;
const startOfDay = (t: number) => {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};
const when = (c: ChatItem): number => {
  const t = Date.parse(c.updated_at ?? c.created_at ?? '');
  return Number.isFinite(t) ? t : 0;
};

/** Case- and accent-insensitive "contains every word", on the name the person sees. */
export function matches(name: string, query: string): boolean {
  const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const hay = fold(name);
  return fold(query).split(/\s+/).filter(Boolean).every((w) => hay.includes(w));
}

/**
 * The list the drawer shows: pinned first, then by how recently each chat was used (Today, Yesterday, the last week, month,
 * older). A search ignores the grouping and shows what matches, archived chats included. Archived chats otherwise stay out of
 * the way, in their own section when asked for.
 */
export function organise(chats: ChatItem[], meta: ChatMeta, opts: { query?: string; showArchived?: boolean; now?: number } = {}): ChatSection[] {
  const now = opts.now ?? Date.now();
  const pinned = new Set(meta.pinned);
  const archived = new Set(meta.archived);
  const rows: ChatRow[] = chats.map((c) => ({ ...c, name: meta.titles[c.id] ?? c.title, pinned: pinned.has(c.id), archived: archived.has(c.id) }));
  const byRecent = (a: ChatRow, b: ChatRow) => when(b) - when(a);
  const q = (opts.query ?? '').trim();
  if (q) {
    const hits = rows.filter((r) => matches(r.name, q)).sort(byRecent);
    return hits.length ? [{ key: 'results', label: `${hits.length} ${hits.length === 1 ? 'result' : 'results'}`, rows: hits }] : [];
  }
  const sections: ChatSection[] = [];
  const pins = meta.pinned.map((id) => rows.find((r) => r.id === id)).filter((r): r is ChatRow => Boolean(r) && !archived.has(r!.id));
  if (pins.length) sections.push({ key: 'pinned', label: 'Pinned', rows: pins });
  const rest = rows.filter((r) => !r.pinned && !r.archived).sort(byRecent);
  const today = startOfDay(now);
  const buckets: Array<[string, string, (t: number) => boolean]> = [
    ['today', 'Today', (t) => t >= today],
    ['yesterday', 'Yesterday', (t) => t >= today - DAY && t < today],
    ['week', 'Previous 7 days', (t) => t >= today - 7 * DAY && t < today - DAY],
    ['month', 'Previous 30 days', (t) => t >= today - 30 * DAY && t < today - 7 * DAY],
    ['older', 'Older', (t) => t < today - 30 * DAY],
  ];
  for (const [key, label, test] of buckets) {
    const inBucket = rest.filter((r) => test(when(r)));
    if (inBucket.length) sections.push({ key, label, rows: inBucket });
  }
  if (opts.showArchived) {
    const old = rows.filter((r) => r.archived).sort(byRecent);
    if (old.length) sections.push({ key: 'archived', label: 'Archived', rows: old });
  }
  return sections;
}

// ---- the live store: one value for every screen, saved on this phone (best effort: a private window can refuse storage)
const listeners = new Set<() => void>();
const read = (): ChatMeta => {
  try {
    return parseMeta(localStorage.getItem(KEY));
  } catch {
    return EMPTY_META;
  }
};
let current: ChatMeta = typeof localStorage === 'undefined' ? EMPTY_META : read();

export const getMeta = (): ChatMeta => current;

export function updateMeta(change: (m: ChatMeta) => ChatMeta): void {
  const next = change(current);
  if (next === current) return;
  current = next;
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
  } catch {
    // not saved, but it still applies until the app is closed
  }
  listeners.forEach((l) => l());
}

export const resetChatMeta = (): void => updateMeta(() => EMPTY_META);

export function useChatMeta(): ChatMeta {
  return useSyncExternalStore(
    (cb) => (listeners.add(cb), () => void listeners.delete(cb)),
    () => current,
    () => EMPTY_META,
  );
}
