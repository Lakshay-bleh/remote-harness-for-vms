import { useCallback, useEffect, useRef, useState } from 'react';
import { escanor } from '../client';
import { ComputerClient, type PairedComputer, type Route } from './lib/client';
import type { ClientMsg, ServerMsg } from './lib/protocol';
import { offlineMessage, retryDelayMs, shouldShowOffline } from './link';

export type LinkState = 'connecting' | 'online' | 'offline';

/**
 * A live link to one paired computer: connects the best way available, checks the computer really answers, and keeps trying again
 * by itself when it does not. A single failed request is not "offline" (it takes two in a row), and an offline computer is retried
 * with a growing pause, when the phone's network comes back, and when the app returns to the foreground.
 */
export function useComputer(computer: PairedComputer) {
  const clientRef = useRef<ComputerClient | null>(null);
  const [state, setState] = useState<LinkState>('connecting');
  const [route, setRoute] = useState<Route | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0); // counts failed connects in a row; 0 once connected
  const failures = useRef(0);
  const pushListeners = useRef(new Set<(m: ServerMsg) => void>());

  const connect = useCallback(async (quiet = false) => {
    const client = clientRef.current;
    if (!client) return;
    if (!quiet) setState('connecting');
    try {
      const used = await client.connect();
      // The cloud route is "connected" as soon as it is available, which says nothing about the computer: ask it something.
      if (used === 'cloud') await client.request({ t: 'ping' }, { timeoutMs: 40_000 });
      if (clientRef.current !== client) return;
      failures.current = 0;
      setAttempt(0);
      setError(null);
      setState('online');
      await client.subscribe(['events']).catch(() => undefined);
    } catch (e) {
      if (clientRef.current !== client) return;
      setState('offline');
      setError(offlineMessage(e, client.route));
      setAttempt((a) => a + 1);
    }
  }, []);

  useEffect(() => {
    const client = new ComputerClient(computer, { relay: ({ agentId, deviceId, sealed }) => escanor.sendToComputer(agentId, deviceId, sealed) });
    clientRef.current = client;
    failures.current = 0;
    setAttempt(0);
    const offRoute = client.onRoute(setRoute);
    const offPush = client.onPush((m) => pushListeners.current.forEach((l) => l(m)));
    void connect();
    return () => {
      offRoute();
      offPush();
      client.close();
      clientRef.current = null;
    };
  }, [computer, connect]);

  // Offline: try again after a pause that grows, and straight away when the network returns or the app is brought back.
  useEffect(() => {
    if (state !== 'offline') return;
    const timer = setTimeout(() => void connect(true), retryDelayMs(attempt));
    const wake = () => (document.visibilityState === 'visible' ? void connect(true) : undefined);
    window.addEventListener('online', wake);
    document.addEventListener('visibilitychange', wake);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('online', wake);
      document.removeEventListener('visibilitychange', wake);
    };
  }, [state, attempt, connect]);

  const request = useCallback(async (msg: ClientMsg): Promise<ServerMsg[]> => {
    const client = clientRef.current;
    if (!client) throw new Error('Not connected.');
    try {
      const out = await client.request(msg);
      failures.current = 0;
      setState('online');
      return out;
    } catch (e) {
      failures.current += 1;
      if (shouldShowOffline(failures.current)) {
        setState('offline');
        setError(offlineMessage(e, client.route));
      }
      throw e;
    }
  }, []);

  const onPush = useCallback((cb: (m: ServerMsg) => void) => {
    pushListeners.current.add(cb);
    return () => void pushListeners.current.delete(cb);
  }, []);

  return { state, route, error, request, onPush, reconnect: () => connect() };
}
