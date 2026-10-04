import type { ReactNode } from 'react';
import PixelDog from './PixelDog';
import type { Scene } from './sprites';

/** A screen with nothing to show yet, or still loading: the dog doing its own thing, a line saying what is going on, and what to do next. */
export function DogState({ scene, title, text, action, scale = 5, live = false }: { scene: Scene; title: string; text?: ReactNode; action?: ReactNode; scale?: number; /** Announce changes (a loading state); an empty state is read once. */ live?: boolean }) {
  return (
    <div className="flex flex-col items-center px-6 py-8 text-center" role={live ? 'status' : undefined} aria-live={live ? 'polite' : undefined}>
      <PixelDog scene={scene} scale={scale} />
      <h2 className="mt-3 font-display text-xl text-ink">{title}</h2>
      {text ? <p className="mt-1 max-w-xs text-[14px] leading-relaxed text-muted">{text}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

/** A small dog trotting along a line, for "loading more" at the end of a list. */
export function DogRunner({ label = 'Loading more…' }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-4 text-[12px] text-muted" role="status">
      <PixelDog scene="run" scale={2} />
      <span>{label}</span>
    </div>
  );
}
