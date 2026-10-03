import { useSyncExternalStore } from 'react';
import { ACCENT_NAMES, applyTheme, type AccentName, type ThemeChoice } from './theme';

/** The things a person can set on this phone only. (Notification choices live on their account, so the website shares them.) */
export interface Prefs {
  /** Scales every size in the app. */
  textSize: 'small' | 'default' | 'large';
  /** A short tap of the vibration motor on tab changes and approvals. */
  haptics: boolean;
  /** Which colours: follow the phone, or always dark, light or pure black. */
  theme: ThemeChoice;
  /** The colour of buttons, links and highlights. */
  accent: AccentName;
  /** No sliding or fading, for people who find motion tiring (or to save a little battery). */
  reduceMotion: boolean;
  /** Which tab the app opens on. */
  startTab: 'assistant' | 'computers' | 'connections' | 'machines';
  /** What a new chat on a machine starts with. Empty = the machine's own default. */
  defaultMode: string;
  defaultModel: string;
  defaultEffort: string;
}

export const DEFAULT_PREFS: Prefs = { textSize: 'default', haptics: true, theme: 'dark', accent: 'gold', reduceMotion: false, startTab: 'assistant', defaultMode: 'default', defaultModel: '', defaultEffort: '' };

export const START_TABS = [
  { value: 'assistant', label: 'Chat' },
  { value: 'computers', label: 'Computers' },
  { value: 'connections', label: 'Connections' },
  { value: 'machines', label: 'Machines' },
] as const;

export const TEXT_SIZE_PERCENT: Record<Prefs['textSize'], number> = { small: 93.75, default: 100, large: 112.5 };

export const PERMISSION_MODES = [
  { value: 'default', label: 'Default', hint: 'Asks before anything that changes things' },
  { value: 'auto', label: 'Auto', hint: 'Decides for itself what is safe' },
  { value: 'acceptEdits', label: 'Accept edits', hint: 'Edits files without asking' },
  { value: 'plan', label: 'Plan mode', hint: 'Plans first, changes nothing' },
  { value: 'dontAsk', label: "Don't ask", hint: 'Never stops to ask' },
  { value: 'bypassPermissions', label: 'Bypass permissions', hint: 'Skips every check. Use with care' },
] as const;

export const MODELS = [
  { value: '', label: 'Machine default' },
  { value: 'claude-sonnet-5-5', label: 'Sonnet 5.5' },
  { value: 'claude-opus-5-5', label: 'Opus 5.5' },
  { value: 'claude-haiku-4-5-20251001', label: 'Haiku 4.5' },
  { value: 'claude-fable-5-1', label: 'Fable 5.1' },
] as const;

export const EFFORTS = [
  { value: '', label: 'Machine default' },
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
  { value: 'xhigh', label: 'xHigh' },
  { value: 'max', label: 'Max' },
] as const;

const KEY = 'escanor.prefs.v1';
const oneOf = <T extends string>(v: unknown, allowed: readonly T[], fallback: T): T => (typeof v === 'string' && (allowed as readonly string[]).includes(v) ? (v as T) : fallback);

/** Read stored preferences defensively: anything damaged or unexpected falls back to the default, field by field. */
export function parsePrefs(raw: string | null): Prefs {
  let v: unknown = null;
  try {
    v = raw ? JSON.parse(raw) : null;
  } catch {
    v = null;
  }
  const o = v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  return {
    textSize: oneOf(o.textSize, ['small', 'default', 'large'] as const, DEFAULT_PREFS.textSize),
    haptics: typeof o.haptics === 'boolean' ? o.haptics : DEFAULT_PREFS.haptics,
    theme: oneOf(o.theme, ['system', 'dark', 'light', 'black'] as const, DEFAULT_PREFS.theme),
    accent: oneOf(o.accent, ACCENT_NAMES, DEFAULT_PREFS.accent),
    reduceMotion: typeof o.reduceMotion === 'boolean' ? o.reduceMotion : DEFAULT_PREFS.reduceMotion,
    startTab: oneOf(o.startTab, START_TABS.map((s) => s.value), DEFAULT_PREFS.startTab),
    defaultMode: oneOf(o.defaultMode, PERMISSION_MODES.map((m) => m.value), DEFAULT_PREFS.defaultMode as (typeof PERMISSION_MODES)[number]['value']),
    defaultModel: oneOf(o.defaultModel, MODELS.map((m) => m.value), DEFAULT_PREFS.defaultModel as (typeof MODELS)[number]['value']),
    defaultEffort: oneOf(o.defaultEffort, EFFORTS.map((m) => m.value), DEFAULT_PREFS.defaultEffort as (typeof EFFORTS)[number]['value']),
  };
}

// ---- the live store (one value, shared by every screen; storage is best effort, since a private window can refuse it)
const listeners = new Set<() => void>();
const read = (): Prefs => {
  try {
    return parsePrefs(localStorage.getItem(KEY));
  } catch {
    return DEFAULT_PREFS;
  }
};
let current: Prefs = typeof localStorage === 'undefined' ? DEFAULT_PREFS : read();

export const getPrefs = (): Prefs => current;

export function applyPrefs(p: Prefs = current): void {
  if (typeof document !== 'undefined') document.documentElement.style.fontSize = `${TEXT_SIZE_PERCENT[p.textSize]}%`;
  applyTheme(p.theme, p.accent, { reduceMotion: p.reduceMotion });
}

// Apply what was saved as the app starts, not only when it is changed: otherwise a chosen text size is lost on every restart.
applyPrefs(current);
if (typeof matchMedia === 'function') matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () => current.theme === 'system' && applyPrefs());

export function setPrefs(patch: Partial<Prefs>): void {
  current = parsePrefs(JSON.stringify({ ...current, ...patch }));
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
  } catch {
    // not saved, but it still applies until the app is closed
  }
  applyPrefs();
  listeners.forEach((l) => l());
}

export function resetPrefs(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    // nothing stored to remove
  }
  current = DEFAULT_PREFS;
  applyPrefs();
  listeners.forEach((l) => l());
}

export function usePrefs(): Prefs {
  return useSyncExternalStore(
    (cb) => (listeners.add(cb), () => void listeners.delete(cb)),
    () => current,
    () => DEFAULT_PREFS,
  );
}

/** A short tap, if the person wants them and the phone can. */
export function haptic(ms = 8): void {
  if (!current.haptics) return;
  try {
    navigator.vibrate?.(ms);
  } catch {
    // unsupported: nothing to do
  }
}
