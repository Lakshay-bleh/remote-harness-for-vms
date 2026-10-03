import { useCallback, useEffect, useRef, useState } from 'react';
import { loadComputers } from '../computer/storage';
import { handleUtterance, type Reply } from './assistant';
import type { VoiceTab } from './commands';
import { chatWithComputer } from './computerChat';
import { deviceOrNull } from './device';
import { ensureMic, listen, speak, stopSpeaking } from './speech';

export type VoicePhase = 'idle' | 'listening' | 'thinking' | 'speaking';

/**
 * One conversation turn with Escanor: listen, understand, do it, say what happened. `start` runs a whole turn; `cancel` stops
 * listening or talking at once.
 */
export function useVoiceSession({ go, onAssistant }: { go: (tab: VoiceTab) => void; onAssistant: (text: string) => Promise<void> }) {
  const [phase, setPhase] = useState<VoicePhase>('idle');
  const [heard, setHeard] = useState('');
  const [reply, setReply] = useState<Reply | null>(null);
  const abort = useRef<AbortController | null>(null);
  const latest = useRef({ go, onAssistant });
  latest.current = { go, onAssistant };
  const turn = useRef(0);

  const cancel = useCallback(() => {
    turn.current += 1;
    abort.current?.abort();
    void stopSpeaking();
    setPhase('idle');
  }, []);

  const start = useCallback(async () => {
    cancel();
    const mine = turn.current;
    const alive = () => turn.current === mine;
    setHeard('');
    setReply(null);

    const mic = await ensureMic();
    if (!alive()) return;
    if (mic !== 'granted') {
      setReply({
        ok: false,
        say: mic === 'denied' ? 'I need the microphone. In Android Settings, open Apps, then Escanor, then Permissions, and allow the microphone.' : 'Voice needs the Escanor Android app with speech recognition on this phone.',
      });
      return;
    }

    setPhase('listening');
    abort.current = new AbortController();
    let said = '';
    try {
      said = await listen({ onPartial: (t) => alive() && setHeard(t), signal: abort.current.signal });
    } catch (e) {
      if (alive()) {
        setReply({ ok: false, say: `I couldn’t hear you. ${e instanceof Error ? e.message : ''} Check the microphone permission in Android Settings, under Apps, Escanor.`.trim() });
        setPhase('idle');
      }
      return;
    }
    if (!alive()) return;
    setHeard(said);
    setPhase('thinking');

    const computers = loadComputers();
    const r = await handleUtterance(said, {
      device: deviceOrNull(),
      hasComputer: computers.length > 0,
      toComputer: (text) => chatWithComputer(computers[0], text),
      toAssistant: (text) => latest.current.onAssistant(text),
      go: (tab) => latest.current.go(tab),
    });
    if (!alive()) return;
    setReply(r);
    setPhase('speaking');
    await speak(r.say);
    if (alive()) setPhase('idle');
  }, [cancel]);

  useEffect(() => () => void stopSpeaking(), []);
  return { phase, heard, reply, start, cancel };
}
