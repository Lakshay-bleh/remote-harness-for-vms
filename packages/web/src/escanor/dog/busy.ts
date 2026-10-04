import { useSyncExternalStore } from 'react';
import type { Scene } from './sprites.ts';

/**
 * How many things are loading right now, anywhere in the app. The companion runs while this is above zero, so the whole app has one
 * honest "working on it" signal instead of each screen inventing its own. Count a load with `trackBusy(promise)`.
 */
let count = 0;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

export function beginBusy(): () => void {
  count += 1;
  emit();
  let done = false;
  return () => {
    if (done) return;
    done = true;
    count = Math.max(0, count - 1);
    emit();
  };
}

/** Counts `work` as busy until it settles, and hands its result (or error) through untouched. */
export function trackBusy<T>(work: Promise<T>): Promise<T> {
  const end = beginBusy();
  return work.finally(end);
}

export const busyCount = (): number => count;

export function useBusyCount(): number {
  return useSyncExternalStore((cb) => (listeners.add(cb), () => void listeners.delete(cb)), () => count, () => 0);
}

/** Which scene the companion plays: working beats everything, then sleep, then the sit-and-sniff routine. */
export function buddyScene(o: { busy: boolean; asleep: boolean; sniffing: boolean }): Scene {
  return o.busy ? 'run' : o.asleep ? 'sleep' : o.sniffing ? 'sniff' : 'sit';
}
