/**
 * The companion wandering the screen. Pure planning, so every walk can be tested without a browser: `planExcursion` turns a kind of
 * outing and the size of the screen into a list of legs (go here, in this scene, facing this way, standing on this edge), and `sample`
 * says where the companion is at any moment of it. Positions are the centre of the picture, in pixels.
 *
 * The five outings: a `stroll` along the bottom and back; a `patrol` all the way round the edge of the screen (up a side, across the top
 * upside down, down the other side); a `peek` where it leaves, then looks in from the edge; `zoomies` (it spins in the middle and dashes
 * about); and a `nap` in the far corner.
 */
import type { Scene } from './sprites.ts';

export type Excursion = 'stroll' | 'patrol' | 'peek' | 'zoomies' | 'nap';
export const EXCURSIONS: Excursion[] = ['stroll', 'patrol', 'peek', 'zoomies', 'nap'];

export interface Vec {
  x: number;
  y: number;
}

/** The screen and the picture. `home` is the centre of the picture at rest; `top` is how far down the top edge is (a header, a status bar). */
export interface Geometry {
  vw: number;
  vh: number;
  sw: number;
  sh: number;
  home: Vec;
  top: number;
}

export interface Leg {
  to: Vec;
  ms: number;
  scene: Scene;
  /** Which way is "down" for the animal: (0,1) on the floor, (-1,0) on the left wall, (0,-1) on the ceiling. */
  feet: Vec;
  /** Which way it is facing. */
  face: Vec;
  /** Start from `to` instead of sliding there from where the last leg ended (coming in from off the screen). */
  jump?: boolean;
}

export interface Plan {
  kind: Excursion;
  legs: Leg[];
  total: number;
}

/** Walking pace in pixels a millisecond; the dash is twice that. */
export const WALK = 0.12;
export const DASH = 0.26;

const v = (x: number, y: number): Vec => ({ x, y });
const FLOOR_FEET = v(0, 1);
const dist = (a: Vec, b: Vec) => Math.hypot(a.x - b.x, a.y - b.y);

/** How to turn the picture (facing right, feet down) so its feet are on `feet` and it faces `face`: a flip, then a quarter-turn clockwise. */
export function orientation(feet: Vec, face: Vec): { rotate: 0 | 90 | 180 | 270; mirror: boolean } {
  for (const mirror of [false, true]) {
    for (const rotate of [0, 90, 180, 270] as const) {
      const a = (rotate * Math.PI) / 180;
      const rot = (p: Vec): Vec => v(Math.round(p.x * Math.cos(a) - p.y * Math.sin(a)), Math.round(p.x * Math.sin(a) + p.y * Math.cos(a)));
      const f = rot(v(0, 1));
      const c = rot(v(mirror ? -1 : 1, 0));
      if (f.x === feet.x && f.y === feet.y && c.x === face.x && c.y === face.y) return { rotate, mirror };
    }
  }
  return { rotate: 0, mirror: false };
}

/** The CSS transform for an orientation (the flip happens first, then the turn). */
export function cssFor(o: { rotate: number; mirror: boolean }): string {
  return `rotate(${o.rotate}deg) scaleX(${o.mirror ? -1 : 1})`;
}

/** The edges: where the picture's centre sits when it is walking along each. */
function edges(g: Geometry) {
  const floor = g.home.y;
  return {
    floor,
    left: g.sh / 2 + 2,
    right: g.vw - g.sh / 2 - 2,
    ceiling: g.top + g.sh / 2,
    minX: g.sw / 2 + 2,
    maxX: g.vw - g.sw / 2 - 2,
    wallTop: g.top + g.sw / 2,
  };
}

const leg = (from: Vec, to: Vec, scene: Scene, feet: Vec, face: Vec, speed = WALK, jump = false): Leg => ({ to, ms: Math.max(1, Math.round(dist(from, to) / speed)), scene, feet, face, jump });
const hold = (at: Vec, ms: number, scene: Scene, feet: Vec, face: Vec): Leg => ({ to: at, ms, scene, feet, face });
const RIGHT = v(1, 0);
const LEFT = v(-1, 0);

/** One outing, starting from home. `rand` gives numbers from 0 up to (not including) 1, so a test can fix the dice. */
export function planExcursion(kind: Excursion, g: Geometry, rand: () => number = Math.random): Plan {
  const e = edges(g);
  const home = g.home;
  const legs: Leg[] = [];
  let at = home;
  const go = (to: Vec, scene: Scene, feet: Vec, face: Vec, speed = WALK, jump = false) => {
    legs.push(leg(jump ? to : at, to, scene, feet, face, speed, jump));
    at = to;
  };
  const stay = (ms: number, scene: Scene, feet: Vec, face: Vec) => legs.push(hold(at, ms, scene, feet, face));

  switch (kind) {
    case 'stroll': {
      const far = v(Math.max(home.x + 40, e.maxX - 6), e.floor);
      go(far, 'run', FLOOR_FEET, RIGHT);
      stay(3000, 'sniff', FLOOR_FEET, RIGHT);
      go(home, 'run', FLOOR_FEET, LEFT);
      break;
    }
    case 'patrol': {
      // clockwise or the other way round, by the dice
      const clockwise = rand() < 0.5;
      const L = (y: number) => v(e.left, y);
      const R = (y: number) => v(e.right, y);
      if (clockwise) {
        go(v(e.minX, e.floor), 'run', FLOOR_FEET, LEFT);
        go(L(e.wallTop), 'run', LEFT, v(0, -1));
        go(v(e.left, e.ceiling), 'run', v(0, -1), RIGHT);
        go(v(e.right, e.ceiling), 'run', v(0, -1), RIGHT);
        go(R(e.floor), 'run', RIGHT, v(0, 1));
        go(home, 'run', FLOOR_FEET, LEFT);
      } else {
        go(v(e.maxX, e.floor), 'run', FLOOR_FEET, RIGHT);
        go(R(e.wallTop), 'run', RIGHT, v(0, -1));
        go(v(e.right, e.ceiling), 'run', v(0, -1), LEFT);
        go(v(e.left, e.ceiling), 'run', v(0, -1), LEFT);
        go(L(e.floor), 'run', LEFT, v(0, 1));
        go(home, 'run', FLOOR_FEET, RIGHT);
      }
      break;
    }
    case 'peek': {
      const out = v(g.vw + g.sw / 2 + 12, e.floor);
      go(out, 'run', FLOOR_FEET, RIGHT);
      stay(2500, 'sleep', FLOOR_FEET, LEFT); // out of sight
      go(v(g.vw - g.sw * 0.42, e.floor), 'sniff', FLOOR_FEET, LEFT, 0.12);
      stay(3200, 'sniff', FLOOR_FEET, LEFT);
      go(out, 'run', FLOOR_FEET, RIGHT, DASH);
      go(v(-g.sw / 2 - 12, e.floor), 'run', FLOOR_FEET, RIGHT, WALK, true);
      go(home, 'run', FLOOR_FEET, RIGHT);
      break;
    }
    case 'zoomies': {
      const mid = v(Math.min(e.maxX - 20, Math.max(home.x + 60, g.vw * (0.4 + rand() * 0.25))), e.floor);
      go(mid, 'run', FLOOR_FEET, RIGHT);
      stay(3400, 'react', FLOOR_FEET, RIGHT);
      go(v(e.maxX, e.floor), 'run', FLOOR_FEET, RIGHT, DASH);
      go(home, 'run', FLOOR_FEET, LEFT, DASH);
      break;
    }
    case 'nap': {
      const bed = v(e.maxX - 8, e.floor);
      go(bed, 'run', FLOOR_FEET, RIGHT);
      stay(9000, 'sleep', FLOOR_FEET, RIGHT);
      stay(1400, 'sniff', FLOOR_FEET, LEFT);
      go(home, 'run', FLOOR_FEET, LEFT);
      break;
    }
  }
  return { kind, legs, total: legs.reduce((n, l) => n + l.ms, 0) };
}

export interface Sample {
  pos: Vec;
  leg: Leg;
  done: boolean;
}

/** Where the companion is `t` milliseconds into an outing. */
export function sample(plan: Plan, home: Vec, t: number): Sample {
  let from = home;
  let start = 0;
  for (const l of plan.legs) {
    const begin = l.jump ? l.to : from;
    if (t < start + l.ms) {
      const k = Math.max(0, Math.min(1, (t - start) / l.ms));
      return { pos: v(begin.x + (l.to.x - begin.x) * k, begin.y + (l.to.y - begin.y) * k), leg: l, done: false };
    }
    start += l.ms;
    from = l.to;
  }
  const last = plan.legs[plan.legs.length - 1];
  return { pos: last.to, leg: last, done: true };
}

/** How long to wait before the next outing, in milliseconds: the first comes sooner, then every one to three minutes. */
export function nextDelay(rand: () => number, first = false): number {
  return first ? Math.round(20_000 + rand() * 40_000) : Math.round(60_000 + rand() * 120_000);
}

/** Which outing next: any, but never the same twice running. */
export function pickExcursion(rand: () => number, last?: Excursion): Excursion {
  const choices = EXCURSIONS.filter((k) => k !== last);
  return choices[Math.min(choices.length - 1, Math.floor(rand() * choices.length))];
}
