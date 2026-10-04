/**
 * What each companion sounds like when it is tapped, made on the spot with the browser's audio (no sound files to download).
 * `VOICES` is plain data: each animal has a few short "calls", each a handful of notes (a pitch that glides from one value to
 * another, with a waveform, a loudness, and optionally a wobble and a muffling filter). `playVoice` turns one into sound.
 */
import type { Animal } from './animals.ts';

export interface Note {
  /** Seconds after the call starts. */
  at: number;
  dur: number;
  /** Pitch in Hz at the start and at the end of the note. */
  from: number;
  to: number;
  wave: 'sine' | 'triangle' | 'sawtooth' | 'square';
  gain: number;
  /** Wobble: [times a second, how many Hz]. */
  vibrato?: [number, number];
  /** Muffle everything above this many Hz. */
  lowpass?: number;
  /** A burst of breath or noise mixed in, 0 to 1. */
  noise?: number;
}

const bark = (at: number, f: number): Note => ({ at, dur: 0.15, from: f, to: f * 0.5, wave: 'sawtooth', gain: 0.45, lowpass: 1500, noise: 0.25 });

export const VOICES: Record<Animal, Note[][]> = {
  dog: [
    [bark(0, 260), bark(0.24, 240)],
    [bark(0, 300), bark(0.2, 280), bark(0.4, 250)],
  ],
  unicorn: [
    [
      { at: 0, dur: 0.18, from: 700, to: 1150, wave: 'sawtooth', gain: 0.3, vibrato: [20, 40], lowpass: 2600 },
      { at: 0.18, dur: 0.55, from: 1150, to: 520, wave: 'sawtooth', gain: 0.3, vibrato: [22, 45], lowpass: 2600 },
      { at: 0.7, dur: 0.25, from: 2400, to: 2400, wave: 'sine', gain: 0.12, vibrato: [6, 30] },
      { at: 0.85, dur: 0.25, from: 3100, to: 3100, wave: 'sine', gain: 0.1 },
    ],
  ],
  pigeon: [
    [
      { at: 0, dur: 0.2, from: 320, to: 250, wave: 'sine', gain: 0.5, vibrato: [9, 14] },
      { at: 0.3, dur: 0.2, from: 320, to: 250, wave: 'sine', gain: 0.5, vibrato: [9, 14] },
      { at: 0.6, dur: 0.55, from: 300, to: 200, wave: 'sine', gain: 0.55, vibrato: [8, 18] },
    ],
  ],
  hamster: [
    [
      { at: 0, dur: 0.07, from: 2100, to: 3200, wave: 'sine', gain: 0.25 },
      { at: 0.12, dur: 0.07, from: 2200, to: 3300, wave: 'sine', gain: 0.25 },
      { at: 0.3, dur: 0.1, from: 2000, to: 3400, wave: 'sine', gain: 0.25 },
    ],
  ],
  cat: [
    [
      { at: 0, dur: 0.25, from: 420, to: 900, wave: 'triangle', gain: 0.4, vibrato: [6, 12], lowpass: 2400 },
      { at: 0.25, dur: 0.4, from: 900, to: 480, wave: 'triangle', gain: 0.4, vibrato: [7, 16], lowpass: 2000 },
    ],
  ],
  elephant: [
    [
      { at: 0, dur: 0.35, from: 280, to: 580, wave: 'sawtooth', gain: 0.35, vibrato: [7, 12], lowpass: 1900, noise: 0.1 },
      { at: 0.35, dur: 0.5, from: 580, to: 400, wave: 'sawtooth', gain: 0.35, vibrato: [7, 16], lowpass: 1700 },
    ],
  ],
};

/** How long a call lasts, in milliseconds. */
export const callLength = (notes: readonly Note[]): number => Math.round(Math.max(...notes.map((n) => n.at + n.dur)) * 1000);

let audio: AudioContext | null = null;

/** Make a call. Quiet by design, and silent where the browser has no audio or has not allowed it yet. Returns how long it lasts. */
export function playVoice(animal: Animal, pick: number = Math.random()): number {
  const calls = VOICES[animal];
  const notes = calls[Math.min(calls.length - 1, Math.floor(pick * calls.length))];
  try {
    const Ctx = typeof window === 'undefined' ? undefined : window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) return callLength(notes);
    audio ??= new Ctx();
    const ctx = audio;
    if (ctx.state === 'suspended') void ctx.resume();
    const t0 = ctx.currentTime + 0.02;
    const master = ctx.createGain();
    master.gain.value = 0.5;
    master.connect(ctx.destination);
    for (const n of notes) {
      const start = t0 + n.at;
      const end = start + n.dur;
      const osc = ctx.createOscillator();
      osc.type = n.wave;
      osc.frequency.setValueAtTime(n.from, start);
      osc.frequency.linearRampToValueAtTime(n.to, end);
      const env = ctx.createGain();
      env.gain.setValueAtTime(0.0001, start);
      env.gain.linearRampToValueAtTime(n.gain, start + Math.min(0.02, n.dur / 3));
      env.gain.exponentialRampToValueAtTime(0.0001, end);
      let out: AudioNode = env;
      if (n.lowpass) {
        const filter = ctx.createBiquadFilter();
        filter.type = 'lowpass';
        filter.frequency.value = n.lowpass;
        env.connect(filter);
        out = filter;
      }
      osc.connect(env);
      if (n.vibrato) {
        const lfo = ctx.createOscillator();
        const depth = ctx.createGain();
        lfo.frequency.value = n.vibrato[0];
        depth.gain.value = n.vibrato[1];
        lfo.connect(depth);
        depth.connect(osc.frequency);
        lfo.start(start);
        lfo.stop(end + 0.05);
      }
      if (n.noise) {
        const len = Math.max(1, Math.floor(ctx.sampleRate * n.dur));
        const buffer = ctx.createBuffer(1, len, ctx.sampleRate);
        const data = buffer.getChannelData(0);
        for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
        const src = ctx.createBufferSource();
        src.buffer = buffer;
        const g = ctx.createGain();
        g.gain.value = n.gain * n.noise;
        src.connect(g);
        g.connect(master);
        src.start(start);
      }
      out.connect(master);
      osc.start(start);
      osc.stop(end + 0.05);
    }
  } catch {
    // no sound is better than a broken tap
  }
  return callLength(notes);
}
