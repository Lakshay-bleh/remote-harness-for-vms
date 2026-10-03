/**
 * The Escanor dog, drawn in pixels. Every frame is a grid of characters (one per pixel) built from a few shapes and then outlined
 * automatically, so a pose is "where are the head, tail and legs" rather than hundreds of hand-placed dots. Nothing here touches the
 * screen: the grids are plain data, tested for size and colours, and `PixelDog` plays them.
 *
 * Scenes: `run` (loading), `sniff` (looking something up), `dig` (digging up history), `sit` (all clear, wagging), `sleep`
 * (waiting for something to start), `lick` (licking the glass of the screen: "say something").
 */

export type Scene = 'run' | 'sniff' | 'dig' | 'sit' | 'sleep' | 'lick';

/** One character per colour. `.` is clear. */
export const PALETTE: Record<string, string> = {
  f: '#f2a73b', // fur
  d: '#c47f1f', // fur in shade (far legs, ears)
  c: '#fff1d1', // cream: muzzle, chest, paws
  o: '#2a190b', // outline
  n: '#17120c', // eyes and nose
  w: '#ffffff', // shine
  t: '#ff6f91', // tongue
  T: '#d94a70', // tongue shade
  e: '#8a6038', // earth
  E: '#4a301a', // dark earth (the hole)
  b: '#f4efe6', // bone
  B: '#c9bba3', // bone shade
  z: '#aab4ff', // sleep
  h: '#ff5d7a', // heart
  s: '#ffe9a8', // sparkle
  k: '#4fb3ff', // ball
  K: '#2a7fd0', // ball shade
  l: '#4b4b55', // ground
  q: '#cfe9ff', // smear on the glass
  g: '#d9d9e0', // dust
};

/** The characters that belong to the dog itself: only these get an outline. */
const DOG = new Set(['f', 'd', 'c', 'n', 't', 'T', 'w']);

export type Frame = string[];

class Pix {
  readonly cells: string[][];
  constructor(readonly w: number, readonly h: number) {
    this.cells = Array.from({ length: h }, () => Array<string>(w).fill('.'));
  }
  px(x: number, y: number, c: string): this {
    if (x >= 0 && x < this.w && y >= 0 && y < this.h) this.cells[y][x] = c;
    return this;
  }
  rect(x: number, y: number, w: number, h: number, c: string, round = false): this {
    for (let j = 0; j < h; j++)
      for (let i = 0; i < w; i++) {
        if (round && (i === 0 || i === w - 1) && (j === 0 || j === h - 1)) continue;
        this.px(x + i, y + j, c);
      }
    return this;
  }
  /** A limb: 2x2 squares along the points, so a leg can lean and bend. */
  limb(points: Array<[number, number]>, c: string, paw = 'c'): this {
    points.forEach(([x, y], i) => this.rect(x, y, 2, 2, i === points.length - 1 ? paw : c));
    return this;
  }
  /** Put a 1-pixel outline around the dog's own colours. */
  outline(): this {
    const mark: Array<[number, number]> = [];
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) {
        if (this.cells[y][x] !== '.') continue;
        const near = [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].some(([a, b]) => DOG.has(this.cells[b]?.[a] ?? '.'));
        if (near) mark.push([x, y]);
      }
    for (const [x, y] of mark) this.cells[y][x] = 'o';
    return this;
  }
  /** Draw a small picture (rows of characters) at a position. */
  stamp(x: number, y: number, rows: string[]): this {
    rows.forEach((row, j) => [...row].forEach((c, i) => c !== '.' && c !== ' ' && this.px(x + i, y + j, c)));
    return this;
  }
  frame(): Frame {
    return this.cells.map((r) => r.join(''));
  }
}

export const W = 36;
export const H = 22;
const GROUND_Y = 20;
const OX = 2;
const OY = 2;

type Legs = 'stand' | 'runA' | 'runB' | 'walkA' | 'walkB';
type Tail = 'up' | 'mid' | 'low';

interface Side {
  legs: Legs;
  tail?: Tail;
  /** Head height: 0 up, 4 level, 8 down (sniffing). */
  head?: number;
  mouth?: 'closed' | 'pant';
  /** Whole dog up this many pixels (the airborne part of a gallop). */
  lift?: number;
  /** Ears blown back by the wind. */
  ears?: 'down' | 'back';
}

const TAILS: Record<Tail, Array<[number, number]>> = {
  up: [[6, 9], [5, 8], [5, 7], [4, 6], [4, 5]],
  mid: [[6, 9], [5, 9], [4, 8], [3, 7], [3, 6]],
  low: [[6, 10], [5, 10], [4, 11], [3, 11], [2, 12]],
};

/** Leg positions for each pose: [near front, far front, near back, far back], each a path of 2x2 squares. */
const LEGS: Record<Legs, Array<Array<[number, number]>>> = {
  stand: [[[18, 14], [18, 15]], [[15, 14], [15, 15]], [[8, 14], [8, 15]], [[11, 14], [11, 15]]],
  walkA: [[[19, 14], [19, 15]], [[14, 14], [14, 15]], [[7, 14], [7, 15]], [[12, 14], [12, 15]]],
  walkB: [[[16, 14], [16, 15]], [[17, 14], [17, 15]], [[10, 14], [10, 15]], [[9, 14], [9, 15]]],
  runA: [[[18, 14], [20, 15], [22, 16]], [[16, 14], [18, 15], [20, 16]], [[9, 14], [7, 15], [5, 16]], [[12, 14], [10, 15], [8, 16]]],
  runB: [[[17, 14], [16, 15], [15, 16]], [[15, 14], [14, 15], [13, 16]], [[10, 14], [11, 15], [12, 16]], [[12, 14], [13, 15], [14, 16]]],
};

/** A standing, walking or running dog facing right, drawn into `p` at the standard place. */
function sideDog(p: Pix, o: Side, dx = 0, dy = 0): void {
  const x0 = OX + dx;
  const y0 = OY + dy - (o.lift ?? 0);
  const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x0 + x, y0 + y, w, h, c, round);
  const P = (x: number, y: number, c: string) => p.px(x0 + x, y0 + y, c);
  const hy = o.head ?? 0;

  // far legs first, so the body covers their tops
  for (const [i, c] of [[1, 'd'], [3, 'd']] as const) LEGS[o.legs][i].forEach(([x, y], j, a) => R(x, y, 2, 2, j === a.length - 1 ? 'c' : c));
  // tail
  TAILS[o.tail ?? 'up'].forEach(([x, y], i, a) => P(x, y, i === a.length - 1 && o.tail !== 'low' ? 'c' : 'f'));
  // body, belly, haunch
  R(7, 8, 14, 6, 'f', true);
  R(9, 13, 10, 1, 'c');
  R(8, 10, 4, 3, 'd', true);
  // head
  R(19, 4 + hy, 7, 7, 'f', true);
  R(25, 7 + hy, 4, 4, 'c', true);
  P(28, 7 + hy, 'n');
  P(23, 6 + hy, 'n');
  P(23, 5 + hy, 'w');
  if (o.mouth === 'pant') {
    R(26, 10 + hy, 2, 1, 'n');
    R(26, 11 + hy, 2, 2, 't');
    P(27, 12 + hy, 'T');
  } else R(26, 10 + hy, 2, 1, 'n');
  // ear
  if (o.ears === 'back') R(16, 4 + hy, 4, 4, 'd', true);
  else R(18, 5 + hy, 3, 6, 'd', true);
  // near legs on top
  for (const i of [0, 2]) LEGS[o.legs][i].forEach(([x, y], j, a) => R(x, y, 2, 2, j === a.length - 1 ? 'c' : 'f'));
  // the near legs of the standing poses are 2 squares tall: fill the gap so they read as legs, not feet
  if (o.legs === 'stand' || o.legs === 'walkA' || o.legs === 'walkB') for (const i of [0, 1, 2, 3]) LEGS[o.legs][i].forEach(([x, y]) => R(x, y + 1, 2, 1, i % 2 ? 'd' : 'f'));
}

function ground(p: Pix, scroll = 0, dust = false): void {
  for (let x = 0; x < W; x++) p.px(x, GROUND_Y, 'l');
  for (let x = 0; x < W; x++) if ((x + scroll) % 7 === 0) p.px(x, GROUND_Y + 1, 'l');
  if (dust) {
    p.px(1, GROUND_Y - 1, 'g');
    p.px(0, GROUND_Y - 3, 'g');
  }
}

// ---------------------------------------------------------------------------------------------------------------- run

function run(): Frame[] {
  const make = (legs: Legs, lift: number, tail: Tail, scroll: number, ball: number): Frame => {
    const p = new Pix(W, H);
    sideDog(p, { legs, lift, tail, mouth: 'pant', ears: 'back', head: 0 }, -3, 0);
    p.outline();
    ground(p, scroll, true);
    // the ball it chases, bouncing ahead
    const by = [GROUND_Y - 4, GROUND_Y - 7, GROUND_Y - 9, GROUND_Y - 7][ball];
    p.rect(31, by, 3, 3, 'k', true);
    p.px(31, by, 'w');
    p.px(33, by + 2, 'K');
    // speed lines behind
    p.rect(0, 9, 3, 1, 'g');
    p.rect(1, 12, 2, 1, 'g');
    return p.frame();
  };
  return [make('runA', 1, 'up', 0, 0), make('runB', 0, 'mid', 2, 1), make('runA', 1, 'up', 4, 2), make('runB', 0, 'mid', 6, 3)];
}

// --------------------------------------------------------------------------------------------------------------- sniff

function sniff(): Frame[] {
  const legs: Legs[] = ['walkA', 'stand', 'walkB', 'stand'];
  return legs.map((l, i) => {
    const p = new Pix(W, H);
    sideDog(p, { legs: l, head: 7, tail: i % 2 ? 'mid' : 'up', mouth: 'closed' }, -2, 0);
    p.outline();
    ground(p, i * 2);
    // scent: a few sparkles drifting up from the ground in front of the nose
    const s = [[28, 17], [30, 16], [29, 14], [31, 13]];
    s.slice(0, i + 1).forEach(([x, y], j) => p.px(x, y - (i - j), j === i ? 's' : 'g'));
    // the nose twitches
    if (i % 2) p.px(27, GROUND_Y - 4, 'n');
    return p.frame();
  });
}

// ----------------------------------------------------------------------------------------------------------------- sit

const HEART = ['.h.h.', 'hhhhh', '.hhh.', '..h..'];

function sit(): Frame[] {
  const make = (tail: number, heart: number, blink: boolean): Frame => {
    const p = new Pix(W, H);
    const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x + 3, y + 2, w, h, c, round);
    const P = (x: number, y: number, c: string) => p.px(x + 3, y + 2, c);
    // tail sweeping along the ground behind
    [[[4, 15], [3, 15], [2, 14], [1, 14]], [[4, 15], [3, 14], [2, 13], [1, 13]], [[4, 15], [3, 15], [2, 15], [1, 14]], [[4, 15], [3, 14], [2, 13], [2, 12]]][tail].forEach(([x, y], i, a) => P(x, y, i === a.length - 1 ? 'c' : 'f'));
    // haunch, chest and back
    R(5, 9, 9, 8, 'f', true);
    R(7, 11, 4, 4, 'd', true);
    R(11, 5, 7, 12, 'f', true);
    R(16, 7, 2, 7, 'c');
    // hind paw out front, front legs
    R(12, 15, 5, 2, 'c', true);
    R(16, 13, 2, 4, 'c');
    R(14, 13, 2, 4, 'd');
    // head
    R(14, 0, 8, 7, 'f', true);
    R(21, 3, 4, 4, 'c', true);
    P(24, 3, 'n');
    if (blink) R(18, 2, 2, 1, 'n');
    else (P(19, 2, 'n'), P(19, 1, 'w'), P(18, 2, 'n'));
    R(22, 6, 2, 1, 'n');
    R(13, 1, 3, 6, 'd', true);
    p.outline();
    ground(p);
    if (heart > 0) {
      const y = 4 - Math.min(heart - 1, 3);
      p.stamp(28, y, HEART);
    }
    return p.frame();
  };
  return [make(0, 0, false), make(1, 1, false), make(2, 2, false), make(1, 3, true), make(0, 4, false), make(3, 0, false)];
}

// --------------------------------------------------------------------------------------------------------------- sleep

const Z = ['zzz', '..z', '.z.', 'z..', 'zzz'];

function sleep(): Frame[] {
  const make = (breath: number, zs: number): Frame => {
    const p = new Pix(W, H);
    const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x + 3, y + 2, w, h, c, round);
    const P = (x: number, y: number, c: string) => p.px(x + 3, y + 2, c);
    // curled tail
    [[4, 13], [3, 14], [3, 15], [4, 16]].forEach(([x, y]) => P(x, y, 'f'));
    P(4, 16, 'c');
    // body lying down, breathing
    R(5, 10 + breath, 16, 7 - breath, 'f', true);
    R(7, 12 + breath, 5, 4 - breath, 'd', true);
    // front paws forward, head resting on them
    R(21, 14, 7, 3, 'f', true);
    R(25, 14, 3, 3, 'c', true);
    R(20, 8, 7, 7, 'f', true);
    R(25, 11, 4, 4, 'c', true);
    P(28, 11, 'n');
    R(22, 11, 2, 1, 'n'); // closed eye
    R(18, 8, 3, 6, 'd', true);
    p.outline();
    ground(p);
    // the Z rising
    if (zs > 0) p.stamp(28, 6 - (zs - 1) * 2, Z);
    if (zs > 1) p.px(25, 5 - zs, 'z');
    return p.frame();
  };
  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ dig

function dig(): Frame[] {
  const frames: Frame[] = [];
  const UP = 4; // the whole scene sits higher than the others, to leave room for a hole worth looking at
  const GY = GROUND_Y - UP;
  // 12 beats: dig, dig, dig... then the bone comes up, shines, and it begins again
  for (let i = 0; i < 12; i++) {
    const p = new Pix(W, H);
    const near = i % 2 === 0;
    const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x, y - UP, w, h, c, round);
    const P = (x: number, y: number, c: string) => p.px(x, y - UP, c);
    const bob = near ? 0 : 1;
    // the hole, deeper as it goes
    const depth = Math.min(1 + Math.floor(i / 2), 4);
    p.rect(22, GY, 13, depth + 1, 'E');
    p.rect(23, GY + depth + 1, 11, 1, 'E');
    p.px(21, GY, 'e');
    p.px(35, GY, 'e');
    // body: rump up, chest low, head toward the hole
    R(5, 6, 8, 8, 'f', true);
    R(7, 8, 4, 4, 'd', true);
    R(12, 8, 8, 7, 'f', true);
    R(12, 14, 7, 1, 'c');
    // tail wagging up high
    [[4, 8], [3, 7], [3, 6]].forEach(([x, y], k) => P(x + (near ? 0 : 1), y, k === 2 ? 'c' : 'f'));
    // back legs
    R(6, 14, 2, 3, 'f');
    R(10, 14, 2, 3, 'd');
    R(6, 16, 2, 1, 'c');
    R(10, 16, 2, 1, 'c');
    // head down, nose in the dirt, bobbing with each scoop
    R(18, 10 + bob, 7, 7, 'f', true);
    R(24, 13 + bob, 4, 4, 'c', true);
    P(27, 13 + bob, 'n');
    P(22, 12 + bob, 'n');
    P(22, 11 + bob, 'w');
    R(17, 10 + bob, 3, 5, 'd', true);
    // front legs digging: one reaches into the hole, the other pulls back
    const reach = (x: number, y: number, c: string) => (R(x, y, 2, 2, c), R(x + 1, y + 2, 2, 2, c), R(x + 2, y + 3, 2, 1, 'c'));
    if (near) {
      reach(20, 14, 'f');
      R(16, 15, 2, 3, 'd');
      R(16, 17, 2, 1, 'c');
    } else {
      reach(18, 14, 'd');
      R(21, 15, 2, 3, 'f');
      R(21, 17, 2, 1, 'c');
    }
    p.outline();
    // dirt flying backward over the dog
    const flying: Array<[number, number]> = [[17, 11], [13, 6], [9, 3], [5, 5], [2, 9]];
    for (let k = 0; k < 3; k++) {
      const [x, y] = flying[(i + k) % 5];
      P(x, y, k === 0 ? 'e' : 'E');
      P(x + 1, y, 'e');
      P(x, y + 1, 'e');
    }
    // the ground, and the heap beside the hole
    for (let x = 0; x < 22; x++) p.px(x, GY, 'l');
    for (let x = 36; x < W; x++) p.px(x, GY, 'l');
    for (let x = 0; x < W; x++) if (x < 22 && (x + i) % 7 === 0) p.px(x, GY + 1, 'l');
    // the bone, at the end
    if (i >= 9) {
      const up = i === 9 ? 0 : i === 10 ? 3 : 5;
      p.stamp(26, GY - up + 1 - 3, ['b..b', 'bbbb', 'B..B']);
      p.rect(24, GY, 11, 1, 'E');
      if (i >= 10) (p.px(24, GY - 7, 's'), p.px(31, GY - 8, 's'), p.px(33, GY - 5, 's'));
    }
    frames.push(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ lick

/** A dog's face pressed against the glass, tongue sweeping across it. */
function lick(): Frame[] {
  const frames: Frame[] = [];
  // the tongue's x position and how far it hangs, per beat; smears are left where it has been
  const sweep: Array<[number, number]> = [[16, 1], [14, 3], [11, 4], [9, 4], [12, 4], [15, 4], [18, 4], [21, 4], [24, 3], [18, 2], [16, 1], [16, 0]];
  const trail: Array<[number, number]> = [];
  sweep.forEach(([tx, len], i) => {
    const p = new Pix(W, H);
    const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x, y, w, h, c, round);
    // ears, head, muzzle
    R(6, 2, 5, 11, 'd', true);
    R(25, 2, 5, 11, 'd', true);
    R(9, 2, 18, 15, 'f', true);
    R(13, 10, 10, 7, 'c', true);
    R(16, 9, 4, 2, 'n');
    p.px(16, 9, 'n');
    // eyes
    R(12, 6, 2, 3, 'n');
    R(22, 6, 2, 3, 'n');
    p.px(12, 6, 'w');
    p.px(22, 6, 'w');
    // mouth
    p.px(17, 11, 'n');
    p.px(18, 11, 'n');
    p.px(15, 13, 'n');
    p.px(20, 13, 'n');
    R(16, 12, 4, 1, 'n');
    // tongue out, wide and flat
    if (len > 0) {
      R(tx - 1 + 0, 13, 4, len, 't', true);
      p.px(tx + 1, 13 + len - 1, 'T');
    }
    p.outline();
    // the smear it leaves on the glass, fading
    if (len >= 3) trail.push([tx, 13 + len]);
    trail.slice(-5).forEach(([x, y], k, a) => {
      if (k >= a.length - 4) for (let j = 0; j < 4; j++) p.px(x - 1 + j, y, k === a.length - 1 ? 'q' : 'g');
    });
    // glass: a corner highlight
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    // little sparkles when it is a good lick
    if (len === 4 && i % 3 === 0) p.px(31, 4, 's');
    frames.push(p.frame());
  });
  return frames;
}

export interface SceneDef {
  frames: Frame[];
  /** Milliseconds each frame stays up. */
  frameMs: number;
}

const CACHE = new Map<Scene, SceneDef>();

export function sceneFrames(scene: Scene): SceneDef {
  let s = CACHE.get(scene);
  if (!s) {
    s = { run: { frames: run(), frameMs: 110 }, sniff: { frames: sniff(), frameMs: 260 }, dig: { frames: dig(), frameMs: 170 }, sit: { frames: sit(), frameMs: 280 }, sleep: { frames: sleep(), frameMs: 420 }, lick: { frames: lick(), frameMs: 200 } }[scene];
    CACHE.set(scene, s);
  }
  return s;
}

export const SCENES: Scene[] = ['run', 'sniff', 'dig', 'sit', 'sleep', 'lick'];
