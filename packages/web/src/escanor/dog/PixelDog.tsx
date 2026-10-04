import { useEffect, useRef, useState, type PointerEvent } from 'react';
import { animalInfo, type Animal } from './animals.ts';
import { useCompanion, useCompanionSound } from './companion.ts';
import { playVoice } from './sounds.ts';
import { H, paletteFor, sceneFrames, W, type Frame, type Scene } from './sprites.ts';

/** Paint one frame of pixels, `scale` screen pixels per dog pixel, nothing smoothed. */
export function paint(ctx: CanvasRenderingContext2D, frame: Frame, scale: number, palette: Record<string, string>): void {
  ctx.clearRect(0, 0, W * scale, H * scale);
  for (let y = 0; y < frame.length; y++) {
    const row = frame[y];
    for (let x = 0; x < row.length; x++) {
      const colour = palette[row[x]];
      if (!colour) continue;
      ctx.fillStyle = colour;
      ctx.fillRect(x * scale, y * scale, scale, scale);
    }
  }
}

const reduced = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

/** How long it reacts to a tap, in milliseconds. */
export const REACT_MS = 2000;

/**
 * A companion playing one scene. Pauses while the page is hidden, and holds still (one frame) for people who asked their phone for
 * less motion. Tap or touch it and it answers in its own way: the scene changes to its `react` scene (the dog spins, the hamster
 * squeaks), a speech bubble says what it says ("Woof!"), and it makes its sound unless that is switched off in Settings > Companion.
 * Loading spinners and other tiny ones are not tappable.
 */
export default function PixelDog({ scene, scale = 6, className = '', animal, interactive = scale >= 2, bubble = true, onTap }: { scene: Scene; scale?: number; className?: string; /** Which animal; the one chosen in Settings when left out. */ animal?: Animal; /** Answers a tap (default for anything not tiny). */ interactive?: boolean; /** Show its own speech bubble (the roaming companion draws its own). */ bubble?: boolean; onTap?: (say: string) => void }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const box = useRef<HTMLSpanElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const chosen = useCompanion();
  const sound = useCompanionSound();
  const which = animal ?? chosen;
  const [reacting, setReacting] = useState(false);
  const [say, setSay] = useState<string | null>(null);
  const [side, setSide] = useState<'centre' | 'left' | 'right'>('centre');
  const shown: Scene = reacting ? 'react' : scene;

  useEffect(() => () => void (timer.current && clearTimeout(timer.current)), []);

  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext('2d');
    if (!el || !ctx) return;
    const { frames, frameMs } = sceneFrames(shown, which);
    const palette = paletteFor(which);
    let i = 0;
    paint(ctx, frames[0], scale, palette);
    if (reduced()) return;
    const tick = setInterval(() => {
      if (document.visibilityState === 'hidden') return;
      i = (i + 1) % frames.length;
      paint(ctx, frames[i], scale, palette);
    }, frameMs);
    return () => clearInterval(tick);
  }, [shown, scale, which]);

  const tap = (e: PointerEvent<HTMLSpanElement>) => {
    const lines = animalInfo(which).says;
    const line = lines[Math.floor(Math.random() * lines.length)];
    const r = box.current?.getBoundingClientRect();
    if (r) setSide(r.left < 70 ? 'left' : r.right > window.innerWidth - 70 ? 'right' : 'centre');
    setSay(line);
    setReacting(true);
    if (sound) playVoice(which);
    onTap?.(line);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      setReacting(false);
      setSay(null);
    }, REACT_MS);
    e.stopPropagation();
  };

  const picture = <canvas ref={canvas} width={W * scale} height={H * scale} aria-hidden="true" className={`select-none [image-rendering:pixelated] ${className}`} style={{ width: W * scale, height: H * scale, maxWidth: '100%' }} />;
  if (!interactive) return picture;
  return (
    <span ref={box} onPointerDown={tap} className="relative inline-block" style={{ cursor: 'pointer', touchAction: 'manipulation', WebkitTapHighlightColor: 'transparent' }}>
      {picture}
      {bubble && say ? (
        <span aria-hidden="true" className="pointer-events-none absolute bottom-full z-50 mb-1 whitespace-nowrap rounded-xl px-2.5 py-1 text-[12px] font-bold leading-none"
          style={{ background: '#fff', color: '#111', border: '2px solid #111', boxShadow: '2px 2px 0 rgba(0,0,0,.35)', ...(side === 'left' ? { left: 0 } : side === 'right' ? { right: 0 } : { left: '50%', transform: 'translateX(-50%)' }) }}>
          {say}
        </span>
      ) : null}
    </span>
  );
}
