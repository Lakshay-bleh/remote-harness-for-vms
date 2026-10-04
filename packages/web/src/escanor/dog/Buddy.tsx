import { useEffect, useState } from 'react';
import type { Animal } from './animals.ts';
import { buddyScene, useBusyCount } from './busy.ts';
import PixelDog from './PixelDog';

/** How long with no touch, key or scroll before the companion falls asleep. */
export const SLEEP_AFTER_MS = 60_000;
/** While awake and not working it sits, and now and then has a sniff around. */
const SIT_MS = 18_000;
const SNIFF_MS = 5_000;

/**
 * The companion, always there: a small one in the corner of every screen. It runs while anything is loading (`busy`, or the shared
 * count from `trackBusy`), sits and sniffs about when all is quiet, and falls asleep when nobody has touched the screen for a minute.
 * It ignores taps (it never gets in the way) and is decoration only.
 */
export default function Buddy({ busy = false, scale = 2, animal, className = '' }: { busy?: boolean; scale?: number; animal?: Animal; className?: string }) {
  const shared = useBusyCount();
  const [asleep, setAsleep] = useState(false);
  const [sniffing, setSniffing] = useState(false);

  // asleep after a minute of nobody; any touch, key or scroll wakes it
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const arm = () => {
      clearTimeout(timer);
      setAsleep(false);
      timer = setTimeout(() => setAsleep(true), SLEEP_AFTER_MS);
    };
    const events = ['pointerdown', 'pointermove', 'keydown', 'scroll', 'touchstart'] as const;
    events.forEach((e) => window.addEventListener(e, arm, { passive: true }));
    arm();
    return () => {
      clearTimeout(timer);
      events.forEach((e) => window.removeEventListener(e, arm));
    };
  }, []);

  // the sit, sniff, sit routine
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const next = (sniff: boolean) => {
      setSniffing(sniff);
      timer = setTimeout(() => next(!sniff), sniff ? SNIFF_MS : SIT_MS);
    };
    next(false);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div aria-hidden="true" className={`pointer-events-none select-none ${className}`}>
      <PixelDog animal={animal} scene={buddyScene({ busy: busy || shared > 0, asleep, sniffing })} scale={scale} />
    </div>
  );
}
