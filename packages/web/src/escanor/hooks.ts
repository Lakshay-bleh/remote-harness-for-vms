import { useCallback, useEffect, useRef, useState } from 'react';
import { addOptimisticMessage, applyMessages, dropOptimisticMessages, emptyChat, markAnswered, pollDelayMs, type ChatState } from '@remote-harness/shared/escanor';
import { escanor, SessionEnded } from './client';
import { useEscanorSession } from './session';

export interface Loaded<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  reload(): void;
}

/**
 * Load something now, again every `everyMs` (0 = never), and again whenever the app comes back to the
 * foreground. A dead session sends the person to sign-in instead of showing an error.
 */
export function useLoad<T>(load: () => Promise<T>, everyMs = 0, deps: unknown[] = []): Loaded<T> {
  const { sessionEnded } = useEscanorSession();
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);
  const loader = useRef(load);
  loader.current = load;

  useEffect(() => {
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const run = async () => {
      try {
        const next = await loader.current();
        if (live) {
          setData(next);
          setError(null);
        }
      } catch (e) {
        if (e instanceof SessionEnded) sessionEnded();
        else if (live) setError(e instanceof Error ? e.message : 'Something went wrong.');
      } finally {
        if (live) {
          setLoading(false);
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
  }, [everyMs, tick, sessionEnded, ...deps]);

  return { data, error, loading, reload: useCallback(() => setTick((t) => t + 1), []) };
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
    async (text: string) => {
      const clean = text.trim();
      if (!clean) return;
      setError(null);
      stateRef.current = addOptimisticMessage(stateRef.current, clean);
      setState(stateRef.current);
      try {
        const { conversation_id } = await escanor.send(clean, id ?? undefined);
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
