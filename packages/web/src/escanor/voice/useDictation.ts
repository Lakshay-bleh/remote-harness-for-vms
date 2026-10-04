import { useCallback, useEffect, useRef, useState } from 'react';
import { canListen, ensureMic, listen } from './speech';

/** Join what was already typed with what has been heard, with one space between. */
export const joinSpoken = (base: string, heard: string): string => [base.trimEnd(), heard.trim()].filter(Boolean).join(' ');

/**
 * Speak instead of type: the words appear in the message box as they are heard, and the person can fix them before sending. Tapping
 * again stops. What was already in the box stays.
 */
export function useDictation(onText: (text: string) => void) {
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const abort = useRef<AbortController | null>(null);
  const latest = useRef(onText);
  latest.current = onText;

  const stop = useCallback(() => abort.current?.abort(), []);

  const start = useCallback(async (current: string) => {
    setError(null);
    const mic = await ensureMic();
    if (mic !== 'granted') {
      setError(mic === 'denied' ? 'Allow the microphone in Android Settings, under Apps, Escanor, Permissions.' : 'Speaking needs the Escanor Android app, or a browser that can listen (Chrome or Safari).');
      return;
    }
    const ctl = new AbortController();
    abort.current = ctl;
    setListening(true);
    try {
      const said = await listen({ signal: ctl.signal, timeoutMs: 60_000, onPartial: (t) => latest.current(joinSpoken(current, t)) });
      if (said) latest.current(joinSpoken(current, said));
    } catch (e) {
      setError(e instanceof Error && e.message ? e.message : 'I could not hear you.');
    } finally {
      if (abort.current === ctl) abort.current = null;
      setListening(false);
    }
  }, []);

  const toggle = useCallback((current: string) => (abort.current ? stop() : void start(current)), [start, stop]);
  useEffect(() => () => abort.current?.abort(), []);
  return { listening, error, toggle, stop, supported: canListen() };
}
