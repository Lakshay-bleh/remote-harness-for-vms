import { SpeechRecognition } from '@capgo/capacitor-speech-recognition';
import { TextToSpeech } from '@capacitor-community/text-to-speech';
import { isNative } from '../../api';

/** The slice of the speech plugin we use, so the listening logic can be tested with a fake recogniser. */
export interface SpeechPlugin {
  start(o: Record<string, unknown>): Promise<unknown>;
  stop(): Promise<void>;
  addListener(event: string, fn: (e: any) => void): Promise<{ remove: () => Promise<void> }>;
}

export interface ListenOptions {
  /** Called with everything heard so far, as it changes. */
  onPartial?: (text: string) => void;
  signal?: AbortSignal;
  /** Stop and use what was heard if nothing ends it by itself. */
  timeoutMs?: number;
  language?: string;
}

/**
 * Listen for one spoken sentence. Resolves with what was said when the person stops talking (or the time limit passes), with ''
 * if cancelled, and rejects with the recogniser's own message if it fails. Always removes its listeners, so listening twice never
 * answers twice.
 */
export function listenOnce(plugin: SpeechPlugin, opts: ListenOptions = {}): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    let latest = '';
    let started = false; // a "stopped" from the previous session can arrive before this one has begun: ignore it
    let done = false;
    const handles: Array<{ remove: () => Promise<void> }> = [];
    let timer: ReturnType<typeof setTimeout> | undefined;

    const finish = (fn: () => void) => {
      if (done) return;
      done = true;
      if (timer) clearTimeout(timer);
      opts.signal?.removeEventListener('abort', onAbort);
      void Promise.all(handles.map((h) => h.remove().catch(() => undefined))).then(fn, fn);
    };
    const stopPlugin = () => void plugin.stop().catch(() => undefined);
    function onAbort() {
      stopPlugin();
      finish(() => resolve(''));
    }

    void (async () => {
      try {
        handles.push(
          await plugin.addListener('partialResults', (e) => {
            const text = String(e?.matches?.[0] ?? e?.accumulatedText ?? e?.accumulated ?? '');
            if (text && text !== latest) {
              latest = text;
              opts.onPartial?.(text);
            }
          }),
          await plugin.addListener('listeningState', (e) => {
            if (started && (e?.state === 'stopped' || e?.status === 'stopped')) finish(() => resolve(latest));
          }),
          await plugin.addListener('error', (e) => finish(() => reject(new Error(String(e?.message || e?.code || 'Speech recognition failed.'))))),
        );
        if (opts.signal?.aborted) return onAbort();
        opts.signal?.addEventListener('abort', onAbort, { once: true });
        timer = setTimeout(() => {
          stopPlugin();
          finish(() => resolve(latest));
        }, opts.timeoutMs ?? 15_000);
        await plugin.start({ language: opts.language ?? 'en-US', maxResults: 1, partialResults: true, popup: false, muteRecognizerBeep: true, allowForSilence: 1500 });
        started = true;
      } catch (e) {
        finish(() => reject(e instanceof Error ? e : new Error(String(e))));
      }
    })();
  });
}

/** The browser's own recogniser (Chrome and Safari), shaped like the phone plugin, so listening works the same in a browser. */
export function webSpeechPlugin(win: Record<string, any> | undefined = typeof window === 'undefined' ? undefined : (window as unknown as Record<string, any>)): SpeechPlugin | null {
  const Ctor = win?.SpeechRecognition ?? win?.webkitSpeechRecognition;
  if (!Ctor) return null;
  let rec: any = null;
  const handlers: Record<string, Set<(e: any) => void>> = {};
  const emit = (name: string, e: unknown) => handlers[name]?.forEach((h) => h(e));
  return {
    async start(o) {
      rec = new Ctor();
      rec.lang = String(o.language ?? 'en-US');
      rec.interimResults = true;
      rec.continuous = false;
      rec.maxAlternatives = 1;
      rec.onresult = (ev: any) => {
        let text = '';
        for (let i = 0; i < ev.results.length; i++) text += ev.results[i][0].transcript;
        emit('partialResults', { matches: [text.trim()] });
      };
      rec.onerror = (ev: any) => emit('error', { message: ev.error === 'not-allowed' ? 'The microphone is blocked for this page.' : ev.error === 'no-speech' ? '' : String(ev.error ?? 'Speech recognition failed.') });
      rec.onend = () => emit('listeningState', { state: 'stopped' });
      rec.start();
      emit('listeningState', { state: 'started' });
    },
    async stop() {
      try {
        rec?.stop();
      } catch {
        // already stopped
      }
    },
    async addListener(name, fn) {
      (handlers[name] ??= new Set()).add(fn);
      return { remove: async () => void handlers[name]?.delete(fn) };
    },
  };
}

export type MicState = 'granted' | 'denied' | 'unsupported';

/** Ask for the microphone (Android shows its own prompt the first time). */
export async function ensureMic(): Promise<MicState> {
  if (!isNative()) return webSpeechPlugin() ? 'granted' : 'unsupported'; // the browser asks when listening starts
  try {
    if (!(await SpeechRecognition.available()).available) return 'unsupported';
    let p = (await SpeechRecognition.checkPermissions()).speechRecognition;
    if (p !== 'granted') p = (await SpeechRecognition.requestPermissions()).speechRecognition;
    return p === 'granted' ? 'granted' : 'denied';
  } catch {
    return 'unsupported';
  }
}

export const listen = (opts: ListenOptions = {}): Promise<string> => {
  const plugin = isNative() ? (SpeechRecognition as unknown as SpeechPlugin) : webSpeechPlugin();
  if (!plugin) return Promise.reject(new Error('Speech recognition is not available here.'));
  return listenOnce(plugin, opts);
};

/** True where the person can talk to Escanor at all: the Android app, or a browser with speech recognition. */
export const canListen = (): boolean => isNative() || webSpeechPlugin() !== null;

/**
 * Split into pieces a speech engine will finish: whole sentences, packed together up to `max` characters, with a sentence that is
 * itself too long broken at a comma, then at a space. (The same rule as the website's voice: an engine silently stops a long single
 * utterance, so a reply is spoken a sentence or two at a time and nothing is cut.)
 */
export function chunkForSpeech(text: string, max = 200): string[] {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (!cleaned) return [];
  const sentences = cleaned.match(/[^.!?]+(?:[.!?]+(?=\s|$)|$)/g) ?? [cleaned];
  const pieces: string[] = [];
  for (const raw of sentences) {
    let sentence = raw.trim();
    while (sentence.length > max) {
      const window = sentence.slice(0, max);
      // Break at a comma if one is far enough along to make a worthwhile piece, otherwise at the last space.
      const comma = Math.max(window.lastIndexOf(', '), window.lastIndexOf('; '));
      const cut = comma > max * 0.5 ? comma : window.lastIndexOf(' ');
      const at = cut > max * 0.3 ? cut + 1 : max;
      pieces.push(sentence.slice(0, at).trim());
      sentence = sentence.slice(at).trim();
    }
    if (sentence) pieces.push(sentence);
  }
  const chunks: string[] = [];
  for (const piece of pieces) {
    const last = chunks[chunks.length - 1];
    if (last && last.length + piece.length + 1 <= max) chunks[chunks.length - 1] = `${last} ${piece}`;
    else chunks.push(piece);
  }
  return chunks;
}

type VoiceLike = { name: string; lang: string; default?: boolean; localService?: boolean };

/**
 * The best installed voice for a language: the person's own language first, a natural-sounding one ahead of a robotic one.
 * Undefined when nothing matches, so the engine's default speaks.
 */
export function pickVoice<T extends VoiceLike>(voices: readonly T[], language: string): T | undefined {
  const lang = language.toLowerCase();
  const base = lang.split('-')[0];
  const score = (v: T): number => {
    const vl = v.lang.toLowerCase().replace('_', '-');
    let s = 0;
    if (vl === lang) s += 40;
    else if (vl.split('-')[0] === base) s += 25;
    else return -1;
    if (/natural|neural|premium|enhanced|google|samantha|daniel|karen|aria|jenny|ava/i.test(v.name)) s += 12;
    if (/compact|espeak|robot|novelty|bad news|zarvox|whisper|trinoids|bubbles/i.test(v.name)) s -= 30;
    if (v.default) s += 3;
    return s;
  };
  let best: T | undefined;
  let bestScore = 0;
  for (const v of voices) {
    const s = score(v);
    if (s > bestScore) {
      best = v;
      bestScore = s;
    }
  }
  return best;
}

/** Say `text` a piece at a time with `say`, checking `cancelled` before each piece, so stopping takes effect at once. */
export async function speakInPieces(text: string, say: (piece: string) => Promise<void>, cancelled: () => boolean, max = 200): Promise<void> {
  for (const piece of chunkForSpeech(text, max)) {
    if (cancelled()) return;
    await say(piece);
  }
}

const LANG = 'en-US';
/** Bumped by stopSpeaking: whatever was being read stops before its next piece. */
let speechTurn = 0;
/** The phone's chosen voice, by its index in the engine's list (looked up once). */
let nativeVoice: Promise<number | undefined> | null = null;

function phoneVoice(): Promise<number | undefined> {
  nativeVoice ??= TextToSpeech.getSupportedVoices()
    .then(({ voices }) => {
      const v = pickVoice(voices, LANG);
      return v ? voices.indexOf(v) : undefined;
    })
    .catch(() => undefined);
  return nativeVoice;
}

/** Say something out loud, all of it. Resolves when it has finished, is stopped, or at once where nothing can speak. */
export async function speak(text: string): Promise<void> {
  if (!text.trim()) return;
  const mine = ++speechTurn;
  const cancelled = () => speechTurn !== mine;
  if (!isNative()) {
    const synth = typeof window !== 'undefined' ? window.speechSynthesis : undefined;
    if (!synth) return;
    const voice = pickVoice(synth.getVoices?.() ?? [], LANG);
    await speakInPieces(
      text,
      (piece) =>
        new Promise<void>((resolve) => {
          const u = new SpeechSynthesisUtterance(piece);
          u.lang = LANG;
          if (voice) u.voice = voice;
          u.onend = u.onerror = () => resolve();
          synth.speak(u);
        }),
      cancelled,
    );
    return;
  }
  const voice = await phoneVoice();
  try {
    await speakInPieces(text, (piece) => TextToSpeech.speak({ text: piece, lang: LANG, rate: 1.0, pitch: 1.0, volume: 1.0, ...(voice !== undefined ? { voice } : {}) }), cancelled);
  } catch {
    // no voice installed or interrupted: the reply is still on screen
  }
}

export async function stopSpeaking(): Promise<void> {
  speechTurn += 1;
  if (!isNative()) return void (typeof window !== 'undefined' && window.speechSynthesis?.cancel());
  await TextToSpeech.stop().catch(() => undefined);
}
