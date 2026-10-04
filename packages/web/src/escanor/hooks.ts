import { useCallback, useEffect, useRef, useState } from 'react';
import { trackBusy } from './dog/busy.ts';
import { addOptimisticMessage, applyMessages, dropOptimisticMessages, emptyChat, markAnswered, pollDelayMs, type ChatState } from '@remote-harness/shared/escanor';
import { readCache, writeCache, type CachePolicy } from './cache';
import { toApi, withAttachmentNote, type Attachment } from './composer/attachments';
import { escanor, SessionEnded } from './client';
import { useEscanorSession } from './session';

export interface Loaded<T> {
  data: T | null;
  error: string | null;
  /** True only while there is nothing to show yet. */
  loading: boolean;
  /** True while a fresh answer is on its way, even when an earlier one is already showing. */
  refreshing: boolean;
  /** The data on screen is the phone's remembered copy, not yet confirmed. */
  stale: boolean;
  reload(): void;
}

/**
 * Load something now, again every `everyMs` (0 = never), and again whenever the app comes back to the foreground. A dead session
 * sends the person to sign-in instead of showing an error.
 *
 * With a `cache`, what was loaded last time is shown at once and only asked for again when it is older than its time to live;
 * `reload()` always asks. Without one it behaves as before.
 */
export function useLoad<T>(load: () => Promise<T>, everyMs = 0, deps: unknown[] = [], cache?: CachePolicy): Loaded<T> {
  const { sessionEnded } = useEscanorSession();
  const remembered = cache ? readCache<T>(cache) : null;
  const [data, setData] = useState<T | null>(remembered?.value ?? null);
  const [stale, setStale] = useState(Boolean(remembered && !remembered.fresh));
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(!remembered);
  const [refreshing, setRefreshing] = useState(false);
  const [tick, setTick] = useState(0);
  const loader = useRef(load);
  loader.current = load;
  const policy = useRef(cache);
  policy.current = cache;
  const forced = useRef(false);
  const key = cache?.key;

  // A different thing to show (another computer, another page): start from what is remembered for it, or from nothing.
  const firstKey = useRef(key);
  useEffect(() => {
    if (firstKey.current === key) return;
    firstKey.current = key;
    const hit = policy.current ? readCache<T>(policy.current) : null;
    setData(hit?.value ?? null);
    setStale(Boolean(hit && !hit.fresh));
    setLoading(!hit);
    setError(null);
  }, [key]);

  useEffect(() => {
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const run = async () => {
      const force = forced.current;
      forced.current = false;
      const hit = policy.current ? readCache<T>(policy.current) : null;
      // Remembered and still fresh: nothing to ask. (A timed refresh, or reload(), asks anyway.)
      if (hit?.fresh && !force && everyMs === 0) {
        if (live) {
          setData(hit.value);
          setStale(false);
          setLoading(false);
        }
        return;
      }
      if (live) setRefreshing(true);
      try {
        const next = await trackBusy(loader.current());
        if (policy.current) writeCache(policy.current.key, next);
        if (live) {
          setData(next);
          setStale(false);
          setError(null);
        }
      } catch (e) {
        if (e instanceof SessionEnded) sessionEnded();
        else if (live) setError(e instanceof Error ? e.message : 'Something went wrong.');
      } finally {
        if (live) {
          setLoading(false);
          setRefreshing(false);
          if (everyMs > 0) timer = setTimeout(run, everyMs);
        }
      }
    };
    void run();
    const onVisible = () => document.visibilityState === 'visible' && void run();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      live = false;
      if (timer) clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [everyMs, tick, sessionEnded, key, ...deps]);

  return {
    data,
    error,
    loading,
    refreshing,
    stale,
    reload: useCallback(() => {
      forced.current = true;
      setTick((t) => t + 1);
    }, []),
  };
}

/** One conversation: what has been said, whether the assistant is working, and how to talk to it. */
export function useConversation(initialId: string | null, onCreated: (id: string) => void) {
  const { sessionEnded } = useEscanorSession();
  const [id, setId] = useState<string | null>(initialId);
  const [state, setState] = useState<ChatState>(emptyChat);
  const [error, setError] = useState<string | null>(null);
  const stateRef = useRef(state);
  stateRef.current = state;

  // Switching conversations starts from nothing: a cursor from the previous one would hide this one's history.
  useEffect(() => {
    setId(initialId);
    stateRef.current = emptyChat;
    setState(emptyChat);
    setError(null);
  }, [initialId]);

  useEffect(() => {
    if (!id) return;
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const poll = async () => {
      try {
        const res = await escanor.messages(id, stateRef.current.lastId);
        if (!live) return;
        stateRef.current = applyMessages(stateRef.current, res);
        setState(stateRef.current);
        setError(null);
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        if (live) setError(e instanceof Error ? e.message : 'Could not refresh the conversation.');
      }
      if (live) timer = setTimeout(poll, pollDelayMs(stateRef.current));
    };
    void poll();
    return () => {
      live = false;
      if (timer) clearTimeout(timer);
    };
  }, [id, sessionEnded]);

  const send = useCallback(
    async (text: string, attachments: Attachment[] = []) => {
      const clean = text.trim();
      if (!clean && attachments.length === 0) return;
      setError(null);
      stateRef.current = addOptimisticMessage(stateRef.current, withAttachmentNote(clean, attachments));
      setState(stateRef.current);
      try {
        const { conversation_id } = await escanor.send(clean, id ?? undefined, toApi(attachments));
        if (!id) {
          setId(conversation_id);
          onCreated(conversation_id);
        }
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        stateRef.current = dropOptimisticMessages(stateRef.current);
        setState(stateRef.current);
        setError(e instanceof Error ? e.message : 'Could not send that.');
      }
    },
    [id, onCreated, sessionEnded],
  );

  const answer = useCallback(
    async (requestId: string, allow: boolean) => {
      if (!id) return;
      stateRef.current = markAnswered(stateRef.current, requestId, allow);
      setState(stateRef.current);
      try {
        await escanor.answer(id, requestId, allow);
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        setError(e instanceof Error ? e.message : 'Could not send your answer.');
      }
    },
    [id, sessionEnded],
  );

  const stop = useCallback(async () => {
    if (id) await escanor.stop(id).catch(() => undefined);
  }, [id]);

  return { id, state, error, send, answer, stop };
}
