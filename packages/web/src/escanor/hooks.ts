import { useCallback, useEffect, useRef, useState } from 'react';
import { trackBusy } from './dog/busy.ts';
import { addOptimisticMessage, applyMessages, canSendNow, dropOptimisticMessages, emptyChat, markAnswered, pollDelayMs, POLL_FAILURES_TO_REPORT, pressStop, stopStatus, type ChatState, type StopPhase } from '@remote-harness/shared/escanor';
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

const PLAN_CHANGED = 'escanor-plan-changed';

/** Tell every screen that shows the plan or its limits that it changed (paid, switched, cancelled), so none shows the old one. */
export function announcePlanChange(): void {
  window.dispatchEvent(new Event(PLAN_CHANGED));
}

/** Run `reload` whenever the plan changes anywhere in the app. Pass a stable function (a `useLoad` reload is one). */
export function useOnPlanChange(reload: () => void): void {
  useEffect(() => {
    window.addEventListener(PLAN_CHANGED, reload);
    return () => window.removeEventListener(PLAN_CHANGED, reload);
  }, [reload]);
}

/** One conversation: what has been said, whether the assistant is working, and how to talk to it. */
export function useConversation(initialId: string | null, onCreated: (id: string) => void) {
  const { sessionEnded } = useEscanorSession();
  const [id, setId] = useState<string | null>(initialId);
  const idRef = useRef(id);
  idRef.current = id;
  const [state, setState] = useState<ChatState>(emptyChat);
  // What the person did that failed (send, stop, answer), kept until they do something else; polls never clear it.
  const [error, setError] = useState<string | null>(null);
  // Polls that keep failing: said once, cleared by the next one that works.
  const [unreachable, setUnreachable] = useState(false);
  const [stopPhase, setStopPhase] = useState<StopPhase>({ kind: 'idle' });
  const stopRef = useRef(stopPhase);
  const [stuck, setStuck] = useState(false);
  const stateRef = useRef(state);
  stateRef.current = state;
  // The first message of a new chat, while the server has not yet said which conversation it made: a Stop pressed now is kept here.
  const creating = useRef<{ stop: boolean } | null>(null);
  // Ask for news now instead of at the next tick (after a stop, so it shows at once).
  const pollNow = useRef<() => void>(() => undefined);

  const setStop = (next: StopPhase) => {
    stopRef.current = next;
    setStopPhase(next);
  };

  // Switching conversations starts from nothing: a cursor from the previous one would hide this one's history. The chat this hook
  // has just created coming back as `initialId` is not a switch: what is on screen (the message, the stop pressed) stays.
  useEffect(() => {
    if (initialId !== null && initialId === idRef.current) return;
    setId(initialId);
    stateRef.current = emptyChat;
    setState(emptyChat);
    setError(null);
    setUnreachable(false);
    setStop({ kind: 'idle' });
    setStuck(false);
  }, [initialId]);

  useEffect(() => {
    if (!id) return;
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let inFlight = false;
    let again = false;
    let failures = 0;
    const poll = async () => {
      if (inFlight) return void (again = true);
      inFlight = true;
      try {
        const res = await escanor.messages(id, stateRef.current.lastId);
        if (!live) return;
        stateRef.current = applyMessages(stateRef.current, res);
        setState(stateRef.current);
        failures = 0;
        setUnreachable(false);
        const s = stopStatus(stopRef.current, stateRef.current.running);
        if (s.phase !== stopRef.current) setStop(s.phase);
        setStuck(s.stuck);
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        failures += 1;
        if (live && failures >= POLL_FAILURES_TO_REPORT) setUnreachable(true);
      } finally {
        inFlight = false;
      }
      if (!live) return;
      // Failing: back off a little each time, but never give up (the server or the network comes back on its own).
      const delay = again ? 0 : failures > 0 ? Math.min(8000, pollDelayMs(stateRef.current) * 2 ** Math.min(failures, 4)) : pollDelayMs(stateRef.current);
      again = false;
      timer = setTimeout(poll, delay);
    };
    pollNow.current = () => {
      if (timer) clearTimeout(timer);
      void poll();
    };
    void poll();
    return () => {
      live = false;
      pollNow.current = () => undefined;
      if (timer) clearTimeout(timer);
    };
  }, [id, sessionEnded]);

  const sendStop = useCallback(
    async (conversationId: string) => {
      if (idRef.current === conversationId) setStop({ kind: 'sending' });
      try {
        await escanor.stop(conversationId);
        if (idRef.current !== conversationId) return;
        // `stopped: false` means it had already finished: the poll shows the ending either way.
        setStop({ kind: 'sent', at: Date.now() });
        pollNow.current();
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        if (idRef.current !== conversationId) return;
        setStop({ kind: 'idle' });
        setError(`Could not stop it. ${e instanceof Error ? e.message : 'Try again.'}`);
      }
    },
    [sessionEnded],
  );

  const send = useCallback(
    async (text: string, attachments: Attachment[] = [], model?: string) => {
      const clean = text.trim();
      if (!clean && attachments.length === 0) return;
      setError(null);
      setStop({ kind: 'idle' });
      setStuck(false);
      stateRef.current = addOptimisticMessage(stateRef.current, withAttachmentNote(clean, attachments));
      setState(stateRef.current);
      const making = id ? null : { stop: false };
      if (making) creating.current = making;
      try {
        const { conversation_id } = await escanor.send(clean, id ?? undefined, toApi(attachments), model);
        if (!id) {
          idRef.current = conversation_id;
          setId(conversation_id);
          onCreated(conversation_id);
        }
        // Stop was pressed before there was a conversation to stop: stop it now that there is.
        if (making?.stop) void sendStop(conversation_id);
      } catch (e) {
        if (e instanceof SessionEnded) return sessionEnded();
        stateRef.current = dropOptimisticMessages(stateRef.current);
        setState(stateRef.current);
        setStop({ kind: 'idle' });
        setError(e instanceof Error ? e.message : 'Could not send that.');
      } finally {
        if (making && creating.current === making) creating.current = null;
      }
    },
    [id, onCreated, sessionEnded, sendStop],
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
    const { phase, send: now } = pressStop(stopRef.current, Boolean(id), stuck);
    if (phase === stopRef.current) return;
    setError(null);
    setStuck(false);
    if (now && id) return sendStop(id);
    if (creating.current) creating.current.stop = true;
    setStop(phase);
  }, [id, stuck, sendStop]);

  const problem = error ?? (stuck ? 'It is taking a long time to stop. You can send a new message, or try Stop again.' : unreachable ? 'Can’t reach your assistant. Retrying…' : null);
  return {
    id,
    state,
    error: problem,
    stopping: stopPhase.kind !== 'idle' && state.running && !stuck,
    /** Send stays usable while a turn looks lost (a stop the server did not act on, or a server that stopped answering). */
    canSend: canSendNow(state, { stuck, unreachable }),
    send,
    answer,
    stop,
  };
}
