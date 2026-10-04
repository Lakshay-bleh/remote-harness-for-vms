import { useSyncExternalStore } from 'react';

/** What the person chose about voice on this phone. */
export interface VoicePrefs {
  /** Place calls themselves (needs Android's Phone permission); off means the dialer opens with the number filled in. */
  directCalls: boolean;
  /** Listen for "Hey Escanor" in the background. */
  wakeWord: boolean;
}

export const DEFAULT_VOICE_PREFS: VoicePrefs = { directCalls: true, wakeWord: false };
const KEY = 'escanor.voice.v1';

export function parseVoicePrefs(raw: string | null): VoicePrefs {
  let o: Record<string, unknown> = {};
  try {
    const v = raw ? JSON.parse(raw) : null;
    if (v && typeof v === 'object' && !Array.isArray(v)) o = v as Record<string, unknown>;
  } catch {
    o = {};
  }
  return {
    directCalls: typeof o.directCalls === 'boolean' ? o.directCalls : DEFAULT_VOICE_PREFS.directCalls,
    wakeWord: typeof o.wakeWord === 'boolean' ? o.wakeWord : DEFAULT_VOICE_PREFS.wakeWord,
  };
}

const listeners = new Set<() => void>();
let cached: VoicePrefs | null = null;

export function getVoicePrefs(): VoicePrefs {
  if (!cached) {
    try {
      cached = parseVoicePrefs(localStorage.getItem(KEY));
    } catch {
      cached = { ...DEFAULT_VOICE_PREFS };
    }
  }
  return cached;
}

export function setVoicePrefs(patch: Partial<VoicePrefs>): void {
  cached = { ...getVoicePrefs(), ...patch };
  try {
    localStorage.setItem(KEY, JSON.stringify(cached));
  } catch {
    // kept for this visit only
  }
  listeners.forEach((l) => l());
}

export function useVoicePrefs(): VoicePrefs {
  return useSyncExternalStore((cb) => (listeners.add(cb), () => void listeners.delete(cb)), getVoicePrefs, getVoicePrefs);
}
