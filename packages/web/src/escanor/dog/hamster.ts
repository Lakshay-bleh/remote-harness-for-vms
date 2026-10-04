/**
 * Bubbly the hamster: round, with cheeks full of seeds. Drawn from ovals rather than the dog's skeleton, but with the same six scenes:
 * `run` on a wheel, `sniff` after a seed, `dig` a burrow, `sit` nibbling a seed, `sleep` in a ball, `lick` the glass.
 */
import { GROUND_Y, H, Pix, W, type Frame } from './pix.ts';

type Scene = 'run' | 'sniff' | 'dig' | 'sit' | 'sleep' | 'lick' | 'home' | 'react';

const HEART = ['.h.h.', 'hhhhh', '.hhh.', '..h..'];
const Z = ['zzz', '..z', '.z.', 'z..', 'zzz'];

function ground(p: Pix, scroll = 0): void {
  for (let x = 0; x < W; x++) p.px(x, GROUND_Y, 'l');
  for (let x = 0; x < W; x++) if ((x + scroll) % 7 === 0) p.px(x, GROUND_Y + 1, 'l');
}

/** A sunflower seed lying at a position. */
const seed = (p: Pix, x: number, y: number) => {
  p.stamp(x, y, ['.xx.', 'xxxX', '.XX.']);
};

// ------------------------------------------------------------------------------------------------------------------- run

/** On the wheel: the wheel turns (its spokes move), the hamster runs on the spot. */
function run(): Frame[] {
  const frames: Frame[] = [];
  const cx = 18;
  const cy = 10;
  const r = 9;
  for (let i = 0; i < 6; i++) {
    const p = new Pix();
    // the stand
    p.line(cx, cy, cx - 6, GROUND_Y - 1, 'l');
    p.line(cx, cy, cx + 6, GROUND_Y - 1, 'l');
    // the wheel: a ring, and spokes that turn
    for (let a = 0; a < 72; a++) {
      const t = (a / 72) * Math.PI * 2;
      p.px(cx + Math.cos(t) * r, cy + Math.sin(t) * r, 'l');
    }
    for (let k = 0; k < 4; k++) {
      const t = (k / 4) * Math.PI * 2 + (i / 6) * (Math.PI / 2);
      p.line(cx, cy, cx + Math.cos(t) * (r - 1), cy + Math.sin(t) * (r - 1), 'g');
    }
    p.px(cx, cy, 'l');
    // the hamster, bouncing a little, legs scissoring
    const bob = i % 2;
    const by = 14 - bob;
    p.oval(16, by + 1, 5, 3.4, 'f'); // body
    p.oval(16, by + 2, 3.5, 2, 'c'); // belly
    p.oval(22, by - 1, 3.4, 3, 'f'); // head
    p.oval(23, by + 1, 2, 1.6, 'c'); // cheek
    p.px(21, by - 4, 'f'); // ear
    p.px(22, by - 4, 'f');
    p.px(22, by - 3, 't');
    p.px(23, by - 1, 'n'); // eye
    p.px(23, by - 2, 'w');
    p.px(25, by, 't'); // nose
    // legs: front reach forward, back push back, swapping
    const f = i % 3;
    p.rect(20 + (f === 0 ? 2 : f === 1 ? 0 : -1), by + 3, 2, 2, 'c');
    p.rect(12 + (f === 0 ? -2 : f === 1 ? 0 : 1), by + 3, 2, 2, 'c');
    p.rect(17 + (f === 0 ? 0 : f === 1 ? 2 : -1), by + 4, 2, 1, 'f');
    p.outline();
    ground(p);
    frames.push(p.frame());
  }
  return frames;
}

// ----------------------------------------------------------------------------------------------------------------- sniff

function sniff(): Frame[] {
  const frames: Frame[] = [];
  for (let i = 0; i < 4; i++) {
    const p = new Pix();
    const step = [0, 1, 0, -1][i];
    // body
    p.oval(13, 15, 7, 4.5, 'f');
    p.oval(13, 17, 5, 2, 'c');
    p.oval(11, 13, 3, 2, 'd');
    // head low, nose to the ground, twitching
    p.oval(21, 16, 4, 3.5, 'f');
    p.oval(23, 17, 2.4, 2, 'c');
    p.px(20, 12, 'f');
    p.px(21, 12, 'f');
    p.px(20, 13, 't');
    p.px(23, 15, 'n');
    p.px(23, 14, 'w');
    p.px(26 + (i % 2), 18, 't'); // nose
    // little legs walking
    p.rect(8 + step, 18, 2, 2, 'c');
    p.rect(12 - step, 19, 2, 1, 'f');
    p.rect(17 + step, 18, 2, 2, 'c');
    p.rect(20 - step, 19, 2, 1, 'f');
    p.outline();
    ground(p, i * 2);
    // the seed it is after, and the scent drifting up
    seed(p, 29, GROUND_Y - 3);
    [[27, 16], [28, 14], [27, 12], [29, 11]].slice(0, i + 1).forEach(([x, y], k) => p.px(x, y - (i - k), k === i ? 's' : 'g'));
    frames.push(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------- dig

function dig(): Frame[] {
  const frames: Frame[] = [];
  const UP = 3;
  const GY = GROUND_Y - UP;
  for (let i = 0; i < 12; i++) {
    const p = new Pix();
    const near = i % 2 === 0;
    const bob = near ? 0 : 1;
    const BY = GY - 1;
    const depth = Math.min(1 + Math.floor(i / 2), 4);
    p.rect(21, GY, 13, depth + 1, 'E');
    p.rect(22, GY + depth + 1, 11, 1, 'E');
    p.px(20, GY, 'e');
    p.px(34, GY, 'e');
    // rump up, head down at the hole
    p.oval(10, BY - 4 + 0, 7, 5, 'f');
    p.oval(10, BY - 2, 4, 2.5, 'c');
    p.oval(8, BY - 6, 3, 1.6, 'd');
    p.oval(18, BY - 2 + bob, 4, 3.5, 'f');
    p.oval(20, BY - 1 + bob, 2.4, 2, 'c');
    p.px(17, BY - 6 + bob, 'f');
    p.px(18, BY - 6 + bob, 'f');
    p.px(17, BY - 5 + bob, 't');
    p.px(20, BY - 3 + bob, 'n');
    p.px(20, BY - 4 + bob, 'w');
    p.px(23, BY - 1 + bob, 't');
    // back feet, and front paws scooping into the hole
    p.rect(6, BY, 3, 1, 'c');
    p.rect(11, BY, 3, 1, 'c');
    p.rect(near ? 19 : 17, BY - 1, 3, 2, 'c');
    p.rect(near ? 15 : 17, BY, 2, 1, 'c');
    p.outline();
    // dirt flying backward
    const flying: Array<[number, number]> = [[14, GY - 8], [11, GY - 11], [8, GY - 12], [5, GY - 9], [3, GY - 5]];
    for (let k = 0; k < 3; k++) {
      const [x, y] = flying[(i + k) % 5];
      p.px(x, y, k === 0 ? 'e' : 'E');
      p.px(x + 1, y, 'e');
    }
    for (let x = 0; x < 21; x++) p.px(x, GY, 'l');
    for (let x = 35; x < W; x++) p.px(x, GY, 'l');
    for (let x = 0; x < 21; x++) if ((x + i) % 7 === 0) p.px(x, GY + 1, 'l');
    // the seed, at the end
    if (i >= 9) {
      const up = i === 9 ? 0 : i === 10 ? 3 : 5;
      seed(p, 26, GY - up - 1);
      p.rect(23, GY, 11, 1, 'E');
      if (i >= 10) (p.px(23, GY - 7, 's'), p.px(30, GY - 8, 's'), p.px(32, GY - 5, 's'));
    }
    frames.push(p.frame());
  }
  return frames;
}

// --------------------------------------------------------------------------------------------------------------------- sit

/** Sitting up, a seed between its paws, nibbling, cheeks puffed. */
function sit(): Frame[] {
  const frames: Frame[] = [];
  const beats: Array<{ nib: number; heart: number; blink: boolean }> = [
    { nib: 0, heart: 0, blink: false }, { nib: 1, heart: 1, blink: false }, { nib: 0, heart: 2, blink: false },
    { nib: 1, heart: 3, blink: true }, { nib: 0, heart: 4, blink: false }, { nib: 1, heart: 0, blink: false },
  ];
  for (const { nib, heart, blink } of beats) {
    const p = new Pix();
    const hy = nib; // the head dips as it nibbles
    // body, belly, feet
    p.oval(16, 13, 7, 5.6, 'f');
    p.oval(16, 14, 4.5, 4, 'c');
    p.rect(10, 19, 4, 1, 't');
    p.rect(18, 19, 4, 1, 't');
    // head with puffed cheeks
    p.oval(16, 7 + hy, 6, 5, 'f');
    p.oval(11, 9 + hy, 3, 2.6, 'c');
    p.oval(21, 9 + hy, 3, 2.6, 'c');
    // ears
    p.rect(10, 2 + hy, 3, 3, 'f', true);
    p.rect(19, 2 + hy, 3, 3, 'f', true);
    p.px(11, 3 + hy, 't');
    p.px(20, 3 + hy, 't');
    // face
    if (blink) (p.rect(12, 7 + hy, 2, 1, 'n'), p.rect(18, 7 + hy, 2, 1, 'n'));
    else (p.rect(12, 6 + hy, 2, 2, 'n'), p.rect(18, 6 + hy, 2, 2, 'n'), p.px(12, 6 + hy, 'w'), p.px(18, 6 + hy, 'w'));
    p.rect(15, 9 + hy, 2, 1, 't');
    p.px(16, 10 + hy, 'n');
    // paws holding the seed up
    p.rect(11, 12 + hy, 2, 2, 'c');
    p.rect(19, 12 + hy, 2, 2, 'c');
    seed(p, 14, 12 + hy);
    p.outline();
    ground(p);
    if (heart > 0) p.stamp(26, 4 - Math.min(heart - 1, 3), HEART);
    frames.push(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ sleep

function sleep(): Frame[] {
  const make = (breath: number, zs: number): Frame => {
    const p = new Pix();
    // a ball of hamster, rising and falling with each breath
    p.oval(17, 13 - breath * 0.5, 10, 6 + breath * 0.5, 'f');
    p.oval(17, 16, 7, 2.6, 'c');
    p.oval(14, 10 - breath * 0.5, 5, 2.4, 'd');
    // face tucked in at the front
    p.oval(26, 15, 3, 3, 'f');
    p.oval(27, 17, 2, 1.6, 'c');
    p.px(25, 11, 'f');
    p.px(26, 11, 'f');
    p.px(25, 12, 't');
    p.rect(25, 15, 2, 1, 'n'); // closed eye
    p.px(29, 16, 't');
    // a paw and a foot peeking out
    p.rect(22, 18, 3, 2, 'c');
    p.rect(8, 18, 3, 2, 't');
    p.outline();
    ground(p);
    if (zs > 0) p.stamp(28, 4 - (zs - 1) * 2 + 2, Z);
    if (zs > 1) p.px(25, 5 - zs + 3, 'z');
    return p.frame();
  };
  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ lick

const LY = 2;

function lick(): Frame[] {
  const frames: Frame[] = [];
  const sweep: Array<[number, number]> = [[16, 1], [14, 3], [11, 4], [9, 4], [12, 4], [15, 4], [18, 4], [21, 4], [24, 3], [18, 2], [16, 1], [16, 0]];
  const trail: Array<[number, number]> = [];
  sweep.forEach(([tx, len], i) => {
    const p = new Pix();
    const O = (cx: number, cy: number, rx: number, ry: number, c: string) => p.oval(cx, cy + LY, rx, ry, c);
    const Q = (x: number, y: number, c: string) => p.px(x, y + LY, c);
    // round ears, a round face, cheeks puffed out with seeds
    O(10, 3, 3, 3, 'f');
    O(26, 3, 3, 3, 'f');
    O(10, 3, 1.4, 1.4, 't');
    O(26, 3, 1.4, 1.4, 't');
    O(18, 9, 10, 8, 'f');
    O(9, 12, 4.5, 4, 'c');
    O(27, 12, 4.5, 4, 'c');
    O(18, 13, 4, 3, 'c');
    // eyes, nose, mouth
    p.rect(12, 7 + LY, 2, 3, 'n');
    p.rect(22, 7 + LY, 2, 3, 'n');
    Q(12, 7, 'w');
    Q(22, 7, 'w');
    p.rect(17, 10 + LY, 2, 1, 't');
    Q(18, 11, 'n');
    p.rect(16, 12 + LY, 4, 1, 'n');
    // whiskers
    [[5, 11], [4, 13], [30, 11], [31, 13]].forEach(([x, y]) => Q(x, y, 'w'));
    if (len > 0) {
      p.rect(tx - 1, 13 + LY, 4, len, 't', true);
      Q(tx + 1, 13 + len - 1, 'T');
    }
    p.outline();
    if (len >= 3) trail.push([tx, 13 + len]);
    trail.slice(-5).forEach(([x, y], k, a) => {
      if (k >= a.length - 4) for (let j = 0; j < 4; j++) p.px(x - 1 + j, y + LY, k === a.length - 1 ? 'q' : 'g');
    });
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    if (len === 4 && i % 3 === 0) p.px(31, 4, 's');
    frames.push(p.frame());
  });
  return frames;
}

// -------------------------------------------------------------------------------------------------------------------- react

/** Tapped: it stuffs its cheeks, hops, and squeaks, spitting seeds, with its ears going. */
function react(): Frame[] {
  const beats = [
    { hop: 0, cheek: 2.6, open: false }, { hop: 1, cheek: 3.4, open: false }, { hop: 1, cheek: 4, open: true },
    { hop: 0, cheek: 4, open: true }, { hop: 1, cheek: 3.6, open: true }, { hop: 0, cheek: 3, open: false },
    { hop: 1, cheek: 2.8, open: true }, { hop: 0, cheek: 2.6, open: false },
  ];
  return beats.map(({ hop, cheek, open }, i) => {
    const p = new Pix();
    const y = -hop;
    p.oval(16, 14.5 + y, 7, 4.6, 'f');
    p.oval(16, 15.5 + y, 4.5, 3.4, 'c');
    p.rect(10, 18, 4, 1, 't');
    p.rect(18, 18, 4, 1, 't');
    p.oval(16, 8 + y, 6, 5, 'f');
    p.oval(11, 10 + y, cheek, cheek - 0.2, 'c');
    p.oval(21, 10 + y, cheek, cheek - 0.2, 'c');
    p.rect(10, 3 + y + (i % 2), 3, 3, 'f', true);
    p.rect(19, 3 + y + ((i + 1) % 2), 3, 3, 'f', true);
    p.px(11, 4 + y + (i % 2), 't');
    p.px(20, 4 + y + ((i + 1) % 2), 't');
    p.rect(12, 7 + y, 2, 2, 'n');
    p.rect(18, 7 + y, 2, 2, 'n');
    p.px(12, 7 + y, 'w');
    p.px(18, 7 + y, 'w');
    if (open) (p.rect(15, 10 + y, 3, 2, 'n'), p.px(16, 11 + y, 't')); // a squeak
    else (p.rect(15, 10 + y, 2, 1, 't'), p.px(16, 11 + y, 'n'));
    p.rect(11, 13 + y, 2, 2, 'c');
    p.rect(19, 13 + y, 2, 2, 'c');
    p.outline();
    ground(p);
    // seeds spat out of its cheeks, and the "!" of a squeak
    if (open) for (let k = 0; k < 3; k++) p.px(24 + k * 3 + (i % 2), 6 + k * 3 - (i % 3), k % 2 ? 'x' : 'X');
    if (open) p.stamp(27, 2, ['h', 'h', 'h', '.', 'h']);
    return p.frame();
  });
}

// ---------------------------------------------------------------------------------------------------------------------- home

/** At home: its cage, with a wheel that turns, a water bottle, a dish of seeds and bedding. It nibbles a seed by the dish. */
function home(): Frame[] {
  const frames: Frame[] = [];
  for (let i = 0; i < 8; i++) {
    const p = new Pix();
    // the tray and the bedding
    p.rect(3, 18, 30, 2, 'm');
    for (let x = 4; x < 32; x++) p.px(x, 18, (x * 5 + 2) % 7 < 3 ? 'Q' : 'W');
    // the wheel on the right, spokes turning
    const cx = 25;
    const cy = 11;
    for (let a = 0; a < 72; a++) {
      const t = (a / 72) * Math.PI * 2;
      p.px(cx + Math.cos(t) * 6, cy + Math.sin(t) * 6, 'I');
    }
    for (let k = 0; k < 3; k++) {
      const t = (k / 3) * Math.PI * 2 + (i / 8) * (Math.PI * 2 / 3);
      p.line(cx, cy, cx + Math.cos(t) * 5.5, cy + Math.sin(t) * 5.5, 'g');
    }
    p.px(cx, cy, 'I');
    p.line(cx, cy, cx - 3, 18, 'I');
    p.line(cx, cy, cx + 3, 18, 'I');
    // the dish with seeds
    p.rect(5, 16, 5, 2, 'e');
    for (const [x, y] of [[6, 15], [8, 15], [7, 14]] as const) p.px(x, y, 'x');
    // the hamster by the dish, chewing a seed, cheeks pulsing
    const t = new Pix();
    const nib = i % 2;
    t.oval(14, 14, 4, 3.4, 'f');
    t.oval(14, 15, 2.6, 2, 'c');
    t.oval(14, 10 + nib, 3.2, 2.8, 'f');
    t.oval(11.5, 11 + nib, 1.8 + (i % 4 < 2 ? 0.4 : 0), 1.7, 'c');
    t.oval(16.5, 11 + nib, 1.8 + (i % 4 < 2 ? 0.4 : 0), 1.7, 'c');
    t.rect(11, 7 + nib, 2, 2, 'f', true);
    t.rect(16, 7 + nib, 2, 2, 'f', true);
    t.px(12, 8 + nib, 't');
    t.px(17, 8 + nib, 't');
    if (i === 3 || i === 7) t.rect(12, 10, 2, 1, 'n');
    else (t.px(12, 10 + nib, 'n'), t.px(16, 10 + nib, 'n'));
    t.px(14, 12 + nib, 't');
    t.rect(13, 13, 2, 1, 'x');
    t.rect(11, 16, 2, 1, 'c');
    t.rect(16, 16, 2, 1, 'c');
    t.outline();
    p.stamp(0, 0, t.frame());
    // the bottle hanging on the outside, on the left
    p.rect(1, 6, 3, 9, 'a');
    p.rect(1, 5, 3, 1, 'I');
    p.px(2, 15, 'I');
    p.px(2, 16, 'A');
    p.px(2, 9 + (i % 3), 'w');
    // the cage: a rail at the top, bars across the front (over everything), a handle
    p.rect(3, 3, 30, 1, 'I');
    p.rect(3, 2, 30, 1, 'i');
    p.rect(14, 1, 8, 1, 'I');
    for (let x = 6; x < 33; x += 4) for (let y = 4; y < 18; y++) p.px(x, y, y % 5 === 0 ? 'I' : 'i');
    p.rect(3, 4, 1, 14, 'I');
    p.rect(32, 4, 1, 14, 'I');
    ground(p);
    frames.push(p.frame());
  }
  return frames;
}

export function hamsterScene(scene: Scene): Frame[] {
  return { run, sniff, dig, sit, sleep, lick, home, react }[scene]();
}
export { H };
