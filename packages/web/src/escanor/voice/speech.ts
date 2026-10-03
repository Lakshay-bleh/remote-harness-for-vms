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

export type MicState = 'granted' | 'denied' | 'unsupported';

/** Ask for the microphone (Android shows its own prompt the first time). */
export async function ensureMic(): Promise<MicState> {
  if (!isNative()) return 'unsupported';
  try {
    if (!(await SpeechRecognition.available()).available) return 'unsupported';
    let p = (await SpeechRecognition.checkPermissions()).speechRecognition;
    if (p !== 'granted') p = (await SpeechRecognition.requestPermissions()).speechRecognition;
    return p === 'granted' ? 'granted' : 'denied';
  } catch {
    return 'unsupported';
  }
}

export const listen = (opts: ListenOptions = {}): Promise<string> => listenOnce(SpeechRecognition as unknown as SpeechPlugin, opts);

/** Say something out loud. Resolves when it has finished (or immediately where the phone cannot speak). */
export async function speak(text: string): Promise<void> {
  if (!text.trim() || !isNative()) return;
  try {
    await TextToSpeech.speak({ text: text.slice(0, 600), lang: 'en-US', rate: 1.0, pitch: 1.0, volume: 1.0 });
  } catch {
    // no voice installed or interrupted: the reply is still on screen
  }
}

export async function stopSpeaking(): Promise<void> {
  if (!isNative()) return;
  await TextToSpeech.stop().catch(() => undefined);
}
