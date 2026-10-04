import { useEffect, useRef, useState } from 'react';
import type { Animal } from './animals.ts';
import { buddyScene, useBusyCount } from './busy.ts';
import PixelDog, { REACT_MS } from './PixelDog';
import { cssFor, nextDelay, orientation, pickExcursion, planExcursion, sample, type Excursion, type Leg } from './roam.ts';
import { H, W, type Scene } from './sprites.ts';

/** How long with no touch, key or scroll before the companion falls asleep. */
export const SLEEP_AFTER_MS = 60_000;
/** While awake and not working it sits, and now and then has a sniff around. */
const SIT_MS = 18_000;
const SNIFF_MS = 5_000;

const reduced = () => typeof window !== 'undefined' && Boolean(window.matchMedia?.('(prefers-reduced-motion: reduce)').matches);

/**
 * The companion, always there: a small one in the corner of every screen (`className` places it). It runs while anything is loading
 * (`busy`, or the shared count from `trackBusy`), sits and sniffs about when all is quiet, and falls asleep when nobody has touched
 * the screen for a minute. Every minute or two (a random while) it goes for an outing: a stroll along the bottom, a lap right round the
 * edge of the screen (up a side, upside down along the top, down the other side), a peek in from the edge, a spin and a dash, or a nap
 * in the far corner. Tap it and it answers. People who asked for less motion get it standing still in its corner.
 * `top` is how far down the top edge of the screen is (a status bar or header it should not climb over).
 */
export default function Buddy({ busy = false, scale = 2, animal, className = '', top = 8, eager = false, only }: { busy?: boolean; scale?: number; animal?: Animal; className?: string; top?: number; /** Go on outings every few seconds instead of every minute or two (for trying it out). */ eager?: boolean; /** Always this outing (for trying it out). */ only?: Excursion }) {
  const shared = useBusyCount();
  const [asleep, setAsleep] = useState(false);
  const [sniffing, setSniffing] = useState(false);
  const [roaming, setRoaming] = useState(false);
  const [legScene, setLegScene] = useState<Scene | null>(null);
  const [start, setStart] = useState('');
  const [said, setSaid] = useState<{ text: string; x: number; y: number; below: boolean } | null>(null);
  const anchor = useRef<HTMLDivElement>(null);
  const sprite = useRef<HTMLDivElement>(null);
  const live = useRef({ asleep: false, busy: false });
  const sw = W * scale;
  const sh = H * scale;
  const working = busy || shared > 0;
  live.current = { asleep, busy: working };

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

  // the outings
  useEffect(() => {
    if (reduced()) return;
    let alive = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let raf = 0;
    let last: Excursion | undefined;

    const schedule = (ms: number) => {
      timer = setTimeout(go, ms);
    };
    const go = () => {
      if (!alive) return;
      const box = anchor.current?.getBoundingClientRect();
      // not now: the page is hidden, it is asleep, or it is busy working
      if (!box || document.visibilityState === 'hidden' || live.current.asleep || live.current.busy) return schedule(20_000);
      const home = { x: box.left + sw / 2, y: box.top + sh / 2 };
      const kind = only ?? pickExcursion(Math.random, last);
      last = kind;
      const plan = planExcursion(kind, { vw: window.innerWidth, vh: window.innerHeight, sw, sh, home, top }, Math.random);
      let begin = 0;
      let leg: Leg | null = null;
      setStart(`translate(${home.x - sw / 2}px, ${home.y - sh / 2}px)`);
      setRoaming(true);
      const frame = (now: number) => {
        if (!alive) return;
        begin ||= now;
        const s = sample(plan, home, now - begin);
        const el = sprite.current;
        if (el) el.style.transform = `translate(${s.pos.x - sw / 2}px, ${s.pos.y - sh / 2}px) ${cssFor(orientation(s.leg.feet, s.leg.face))}`;
        if (s.leg !== leg) {
          leg = s.leg;
          setLegScene(s.leg.scene);
        }
        if (s.done) {
          setRoaming(false);
          setLegScene(null);
          schedule(eager ? 4000 : nextDelay(Math.random));
          return;
        }
        raf = requestAnimationFrame(frame);
      };
      raf = requestAnimationFrame(frame);
    };
    schedule(eager ? 1500 : nextDelay(Math.random, true));
    return () => {
      alive = false;
      clearTimeout(timer);
      cancelAnimationFrame(raf);
      setRoaming(false);
      setLegScene(null);
    };
  }, [sw, sh, top, eager, only]);

  // a tap: its own speech bubble, drawn upright wherever it is (the picture may be sideways or upside down)
  const tapped = (text: string) => {
    const r = sprite.current?.getBoundingClientRect();
    if (!r) return;
    const x = Math.min(window.innerWidth - 56, Math.max(56, r.left + r.width / 2));
    setSaid({ text, x, y: r.top < 56 ? r.bottom + 6 : r.top - 6, below: r.top < 56 });
    setTimeout(() => setSaid((s) => (s?.text === text ? null : s)), REACT_MS - 200);
  };

  const scene = legScene ?? buddyScene({ busy: working, asleep, sniffing });
  return (
    <>
      <div ref={anchor} aria-hidden="true" className={`pointer-events-none select-none ${className}`} style={{ width: sw, height: sh }}>
        <div ref={sprite} className="pointer-events-auto" style={roaming ? { position: 'fixed', left: 0, top: 0, zIndex: 40, transformOrigin: '50% 50%', willChange: 'transform', transform: start } : undefined}>
          <PixelDog animal={animal} scene={scene} scale={scale} bubble={false} onTap={tapped} />
        </div>
      </div>
      {said ? (
        <div aria-hidden="true" className="pointer-events-none fixed z-50 whitespace-nowrap rounded-xl px-2.5 py-1 text-[12px] font-bold leading-none" style={{ left: said.x, top: said.y, transform: `translate(-50%, ${said.below ? '0' : '-100%'})`, background: '#fff', color: '#111', border: '2px solid #111', boxShadow: '2px 2px 0 rgba(0,0,0,.35)' }}>
          {said.text}
        </div>
      ) : null}
    </>
  );
}
