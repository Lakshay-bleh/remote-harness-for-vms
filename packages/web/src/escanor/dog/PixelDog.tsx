import { useEffect, useRef } from 'react';
import type { Animal } from './animals.ts';
import { useCompanion } from './companion.ts';
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

/**
 * The Escanor dog playing one scene. Pauses while the page is hidden, and holds still (one frame) for people who asked their phone
 * for less motion. It is decoration: hidden from screen readers, with the words on the screen saying what is going on.
 */
export default function PixelDog({ scene, scale = 6, className = '', animal }: { scene: Scene; scale?: number; className?: string; /** Which animal; the one chosen in Settings when left out. */ animal?: Animal }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const chosen = useCompanion();
  const which = animal ?? chosen;

  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext('2d');
    if (!el || !ctx) return;
    const { frames, frameMs } = sceneFrames(scene, which);
    const palette = paletteFor(which);
    let i = 0;
    paint(ctx, frames[0], scale, palette);
    if (reduced()) return;
    const timer = setInterval(() => {
      if (document.visibilityState === 'hidden') return;
      i = (i + 1) % frames.length;
      paint(ctx, frames[i], scale, palette);
    }, frameMs);
    return () => clearInterval(timer);
  }, [scene, scale, which]);

  return <canvas ref={canvas} width={W * scale} height={H * scale} aria-hidden="true" className={`select-none [image-rendering:pixelated] ${className}`} style={{ width: W * scale, height: H * scale, maxWidth: '100%' }} />;
}
