import { useCallback, useEffect, useRef, useState } from 'react';
import { isIOS, isNative } from '../../api';
import { getComputerPrefs } from '../computer/computerPrefs';
import { loadComputers } from '../computer/storage';
import { handleUtterance, type Reply } from './assistant';
import type { VoiceTab } from './commands';
import { forSpeech } from './assistantAnswer';
import { chatWithComputer } from './computerChat';
import { pickComputer } from './computerTarget';
import { deviceOrNull } from './device';
import { resolveOnServer } from './resolve';
import { ensureMic, listen, speak, stopSpeaking } from './speech';
import { getVoicePrefs } from './voicePrefs';

const LAST_COMPUTER = 'escanor.voice.lastComputer.v1';
const lastComputer = (): string | null => {
  try {
    return localStorage.getItem(LAST_COMPUTER);
  } catch {
    return null;
  }
};
const rememberComputer = (id: string) => {
  try {
    localStorage.setItem(LAST_COMPUTER, id);
  } catch {
    // not remembered: the next request without a name goes to the first computer
  }
};

export type VoicePhase = 'idle' | 'listening' | 'thinking' | 'speaking';

/** How one turn ended, so a conversation can decide whether to listen again. */
export type TurnOutcome = 'spoke' | 'silent' | 'stop' | 'cancelled' | 'error';

/**
 * One conversation turn with Escanor: listen, understand, do it, say what happened. `start` runs a whole turn; `cancel` stops
 * listening or talking at once.
 */
export function useVoiceSession({ go, onAssistant }: { go: (tab: VoiceTab) => void; onAssistant: (text: string, signal: AbortSignal) => Promise<string | void> }) {
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

  const start = useCallback(async (): Promise<TurnOutcome> => {
    cancel();
    const mine = turn.current;
    const alive = () => turn.current === mine;
    setHeard('');
    setReply(null);

    const mic = await ensureMic();
    if (!alive()) return 'cancelled';
    if (mic !== 'granted') {
      setReply({
        ok: false,
        say: mic === 'denied' ? 'I need the microphone. ' + (isIOS() ? 'In iPhone Settings, open Escanor and allow the microphone.' : 'In Android Settings, open Apps, then Escanor, then Permissions, and allow the microphone.') + '' : 'Voice needs the Escanor phone app, or a browser that can listen (Chrome or Safari).',
      });
      return 'error';
    }

    setPhase('listening');
    abort.current = new AbortController();
    let said = '';
    try {
      said = await listen({ onPartial: (t) => alive() && setHeard(t), signal: abort.current.signal });
    } catch (e) {
      if (alive()) {
        setReply({ ok: false, say: `I couldn’t hear you. ${e instanceof Error ? e.message : ''} ${isNative() ? (isIOS() ? 'Check the microphone permission in iPhone Settings, under Escanor.' : 'Check the microphone permission in Android Settings, under Apps, Escanor.') : 'Allow the microphone for this page in your browser.'}`.replace(/\s+/g, ' ').trim() });
        setPhase('idle');
      }
      return alive() ? 'error' : 'cancelled';
    }
    if (!alive()) return 'cancelled';
    if (!said.trim()) {
      setPhase('idle');
      return 'silent';
    }
    setHeard(said);
    setPhase('thinking');

    // Each paired computer by the name given on this phone and its own; a request goes to the one named, else the one used last.
    const computers = loadComputers().map((c) => ({ ...c, alias: getComputerPrefs(c.id).alias }));
    const signal = abort.current.signal;
    const r = await handleUtterance(said, {
      device: deviceOrNull(),
      hasComputer: computers.length > 0,
      computerNames: computers.flatMap((c) => (c.alias ? [c.alias, c.name] : [c.name])),
      toComputer: (text, name) => {
        const target = pickComputer(computers, name, lastComputer());
        if (!target) return Promise.reject(new Error('You have not paired a computer yet.'));
        rememberComputer(target.id);
        return chatWithComputer(target, text);
      },
      toAssistant: (text) => latest.current.onAssistant(text, signal),
      go: (tab) => latest.current.go(tab),
      phone: { directCalls: getVoicePrefs().directCalls },
      ack: (t) => speak(forSpeech(t)),
      interim: (t) => alive() && setReply({ ok: true, say: t }),
      resolve: (text) => resolveOnServer(text, deviceOrNull(), { signal }),
    });
    if (!alive()) return 'cancelled';
    setReply(r);
    setPhase('speaking');
    await speak(forSpeech(r.say));
    if (!alive()) return 'cancelled';
    setPhase('idle');
    return r.kind === 'stop' ? 'stop' : 'spoke';
  }, [cancel]);

  useEffect(() => () => void stopSpeaking(), []);
  return { phase, heard, reply, start, cancel };
}
