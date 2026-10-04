import { useCallback, useEffect, useRef, useState } from 'react';
import { readCache, writeCache } from '../cache';

/** How long to wait before trying again after a failure (ms), or null when it is time to stop and say so. */
export function retryDelay(attempt: number): number | null {
  return [1500, 4000, 9000][attempt] ?? null;
}

/** `p`, or a rejection after `ms`: a request over the cloud can otherwise wait for minutes. */
export function withDeadline<T>(p: Promise<T>, ms: number, message = 'The computer took too long to answer.'): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(message)), ms);
    p.then((v) => (clearTimeout(t), resolve(v)), (e) => (clearTimeout(t), reject(e)));
  });
}

export interface RemoteOptions<T> {
  computerId: string;
  /** What is being asked for: part of the cache key ("groups", "activity", "stats"). */
  what: string;
  /** Only ask while the computer is reachable. */
  online: boolean;
  /** Turn this off while the screen is not showing. */
  enabled?: boolean;
  run: () => Promise<T>;
  /** Trusted without asking again for this long. */
  ttlMs: number;
  /** Ask again this often while the screen is showing (the pause is counted from the end of the last answer). */
  everyMs?: number;
  /** Longest to wait for one answer. */
  deadlineMs?: number;
}

export interface Remote<T> {
  data: T | null;
  /** Why the last try failed (shown only when there is nothing else to show). */
  error: unknown;
  /** Nothing to show yet. */
  loading: boolean;
  /** An answer is on its way. */
  refreshing: boolean;
  /** What is on screen was remembered from an earlier visit and is being checked. */
  stale: boolean;
  reload(): void;
  /** Replace what is shown (after something was changed) and remember it. */
  set(v: T): void;
}

/**
 * Ask one of the computer's screens' questions the way a phone app should: show what was remembered at once, ask once at a time,
 * try again by itself a few times when the first try fails, and never leave the person with a spinner that does not end. A failure
 * is only an error when there is nothing remembered to show instead.
 */
export function useRemote<T>(o: RemoteOptions<T>): Remote<T> {
  const key = `computer:${o.computerId}:${o.what}`;
  const policy = { key, ttlMs: o.ttlMs, maxAgeMs: 7 * 24 * 3_600_000 };
  const remembered = readCache<T>(policy);
  const [data, setData] = useState<T | null>(remembered?.value ?? null);
  const [stale, setStale] = useState(Boolean(remembered && !remembered.fresh));
  const [error, setError] = useState<unknown>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [tick, setTick] = useState(0);
  const latest = useRef(o);
  latest.current = o;
  const forced = useRef(false);
  const busy = useRef(false);

  const enabled = o.enabled !== false && o.online;

  useEffect(() => {
    if (!enabled) return;
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let attempt = 0;

    const run = async (): Promise<void> => {
      if (!live || busy.current) return;
      const force = forced.current;
      forced.current = false;
      const hit = readCache<T>(policy);
      if (hit?.fresh && !force && !latest.current.everyMs) {
        setData(hit.value);
        setStale(false);
        return;
      }
      if (document.visibilityState === 'hidden' && !force) {
        timer = setTimeout(run, 2000);
        return;
      }
      busy.current = true;
      setRefreshing(true);
      try {
        const next = await withDeadline(latest.current.run(), latest.current.deadlineMs ?? 30_000);
        writeCache(key, next);
        if (!live) return;
        setData(next);
        setStale(false);
        setError(null);
        attempt = 0;
        if (latest.current.everyMs) timer = setTimeout(run, latest.current.everyMs);
      } catch (e) {
        if (!live) return;
        setError(e);
        const wait = retryDelay(attempt++);
        if (wait !== null) timer = setTimeout(run, wait);
        else if (latest.current.everyMs) timer = setTimeout(run, latest.current.everyMs * 2);
      } finally {
        busy.current = false;
        if (live) setRefreshing(false);
      }
    };
    void run();
    const onVisible = () => document.visibilityState === 'visible' && (clearTimeout(timer), void run());
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      live = false;
      busy.current = false;
      if (timer) clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, key, tick]);

  const reload = useCallback(() => {
    forced.current = true;
    setError(null);
    setTick((t) => t + 1);
  }, []);
  const set = useCallback((v: T) => {
    writeCache(key, v);
    setData(v);
    setStale(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return { data, error, loading: data === null && (refreshing || !error), refreshing, stale, reload, set };
}
