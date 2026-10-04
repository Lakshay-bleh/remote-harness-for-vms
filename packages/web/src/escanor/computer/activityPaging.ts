import type { ActivityItem } from './lib/protocol';

/** How many entries one page holds, and how many more to reveal each time the end of the list scrolls into view. */
export const PAGE = 20;

const keyOf = (a: ActivityItem) => `${a.at}|${a.capabilityId}|${a.caller}|${a.outcome}`;

/** Put a newly fetched page together with what is already loaded: no duplicates, newest first. */
export function mergeActivity(current: ActivityItem[], incoming: ActivityItem[]): ActivityItem[] {
  const seen = new Set<string>();
  const out: ActivityItem[] = [];
  for (const a of [...current, ...incoming].sort((x, y) => y.at.localeCompare(x.at))) {
    const k = keyOf(a);
    if (!seen.has(k)) (seen.add(k), out.push(a));
  }
  return out;
}

/**
 * What to do when the end of the list is reached: show more of what is already here, ask the computer for older entries, or nothing.
 * An older computer ignores page sizes and sends everything at once, so `serverMore` is undefined and only the first applies.
 */
export function nextStep(loaded: number, shown: number, serverMore: boolean | undefined): 'reveal' | 'fetch' | 'done' {
  if (shown < loaded) return 'reveal';
  return serverMore ? 'fetch' : 'done';
}

export const oldest = (items: ActivityItem[]): string | undefined => items.at(-1)?.at;
