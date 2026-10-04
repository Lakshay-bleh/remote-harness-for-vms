/**
 * Riti the pigeon: grey, with a green and purple sheen on the neck and an orange eye. Built from ovals like the hamster, with the same
 * six scenes: `run` (a bobbing walk after a crumb), `sniff` (pecking at the ground), `dig` (scratching up a crumb), `sit` (perched,
 * cooing), `sleep` (puffed up, head tucked in) and `lick` (pecking at the glass).
 */
import { GROUND_Y, Pix, W, type Frame } from './pix.ts';

type Scene = 'run' | 'sniff' | 'dig' | 'sit' | 'sleep' | 'lick';

const HEART = ['.h.h.', 'hhhhh', '.hhh.', '..h..'];
const Z = ['zzz', '..z', '.z.', 'z..', 'zzz'];

function ground(p: Pix, scroll = 0): void {
  for (let x = 0; x < W; x++) p.px(x, GROUND_Y, 'l');
  for (let x = 0; x < W; x++) if ((x + scroll) % 7 === 0) p.px(x, GROUND_Y + 1, 'l');
}

const crumb = (p: Pix, x: number, y: number) => p.stamp(x, y, ['xx', 'xX']);

interface Pose {
  /** Where the head is, relative to a standing pigeon (0, 0). Negative y is up. */
  hx?: number;
  hy?: number;
  /** Body up this many pixels. */
  lift?: number;
  /** Legs: which phase of the walk. */
  legs?: 0 | 1 | 2 | 3;
  /** Pixels to move the whole bird. */
  dx?: number;
  dy?: number;
  beak?: 'closed' | 'open';
  /** Tail raised. */
  tail?: number;
}

/** A pigeon seen from the side, facing right. */
function sidePigeon(p: Pix, o: Pose): void {
  const dx = o.dx ?? 0;
  const dy = (o.dy ?? 0) - (o.lift ?? 0) + 1;
  const hx = o.hx ?? 0;
  const hy = o.hy ?? 0;
  const O = (cx: number, cy: number, rx: number, ry: number, c: string) => p.oval(cx + dx, cy + dy, rx, ry, c);
  const P = (x: number, y: number, c: string) => p.px(x + dx, y + dy, c);
  const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x + dx, y + dy, w, h, c, round);

  // legs and feet first, behind the body
  const legPhase = [[0, 0], [2, -2], [0, 0], [-2, 2]][o.legs ?? 0];
  for (const [i, lx] of [[0, 13], [1, 17]] as const) {
    const sway = legPhase[i];
    p.line(lx + dx + sway * 0.5, 16 + dy, lx + dx + sway, GROUND_Y - 1, 'p');
    p.rect(lx + dx + sway - 1, GROUND_Y - 1, 3, 1, 'p');
  }
  // tail, a wedge behind
  const t = o.tail ?? 0;
  R(3, 11 - t, 6, 3, 'd', true);
  R(2, 13 - t, 4, 2, 'd');
  // body, wing, breast
  O(14, 12, 8, 5, 'f');
  O(21, 13, 4, 4, 'c');
  O(13, 12, 5.5, 3, 'd');
  R(9, 12, 8, 1, 'f');
  // neck, with the sheen, and the head
  const nx = 21 + hx * 0.5;
  const ny = 8 + hy * 0.5;
  O(21, 9, 3.2, 4, 'f');
  if (hx || hy) O(nx, ny, 3.2, 3.2, 'f');
  O(24 + hx, 5 + hy, 3.2, 2.8, 'f');
  R(20 + Math.round(hx * 0.4), 7 + Math.round(hy * 0.5), 3, 2, 'M');
  R(22 + Math.round(hx * 0.6), 8 + Math.round(hy * 0.5), 2, 2, 'N');
  // beak, eye
  R(27 + hx, 5 + hy, 3, 2, 'y');
  P(27 + hx, 5 + hy, 'c');
  if (o.beak === 'open') P(29 + hx, 7 + hy, 'y');
  P(25 + hx, 4 + hy, 'u');
  P(25 + hx, 4 + hy, 'n');
  P(24 + hx, 4 + hy, 'u');
}

// ------------------------------------------------------------------------------------------------------------------- run

function run(): Frame[] {
  const frames: Frame[] = [];
  const poses: Pose[] = [{ legs: 1, hx: 2, lift: 0 }, { legs: 0, hx: 0, lift: 1 }, { legs: 3, hx: -1, lift: 0 }, { legs: 0, hx: 0, lift: 1 }];
  poses.forEach((pose, i) => {
    const p = new Pix();
    sidePigeon(p, { ...pose, dx: 0, tail: 1 });
    p.outline();
    ground(p, i * 2);
    crumb(p, 31, GROUND_Y - [3, 5, 6, 5][i]);
    p.rect(0, 9, 3, 1, 'g');
    p.rect(1, 12, 2, 1, 'g');
    frames.push(p.frame());
  });
  return frames;
}

// ----------------------------------------------------------------------------------------------------------------- sniff

/** Pecking: head up, then down to the ground, then up with a crumb. */
function sniff(): Frame[] {
  const frames: Frame[] = [];
  const heads: Array<{ hx: number; hy: number; legs: 0 | 1 | 2 | 3; open?: boolean }> = [
    { hx: 0, hy: 0, legs: 0 }, { hx: 3, hy: 5, legs: 1 }, { hx: 4, hy: 10, legs: 1, open: true }, { hx: 2, hy: 4, legs: 0 },
  ];
  heads.forEach((h, i) => {
    const p = new Pix();
    sidePigeon(p, { hx: h.hx, hy: h.hy, legs: h.legs, dx: 0, beak: h.open ? 'open' : 'closed', tail: i === 2 ? 2 : 0 });
    p.outline();
    ground(p, i * 2);
    if (i < 3) crumb(p, 30, GROUND_Y - 2);
    else p.px(29, 12, 'x');
    [[30, 17], [32, 16]].slice(0, i).forEach(([x, y]) => p.px(x, y, 's'));
    frames.push(p.frame());
  });
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------- dig

/** Scratching up a crumb: head down at a hole, a foot kicking dirt back, and the crumb comes up. */
function dig(): Frame[] {
  const frames: Frame[] = [];
  const UP = 2;
  const GY = GROUND_Y - UP;
  for (let i = 0; i < 12; i++) {
    const p = new Pix();
    const near = i % 2 === 0;
    const depth = Math.min(1 + Math.floor(i / 2), 4);
    p.rect(24, GY, 11, depth + 1, 'E');
    p.rect(25, GY + depth + 1, 9, 1, 'E');
    p.px(23, GY, 'e');
    p.px(35, GY, 'e');
    sidePigeon(p, { hx: 4, hy: near ? 12 : 10, dx: 0, dy: -UP, legs: near ? 1 : 3, beak: near ? 'open' : 'closed', tail: 2 });
    p.outline();
    const flying: Array<[number, number]> = [[16, GY - 2], [12, GY - 6], [8, GY - 8], [4, GY - 6], [2, GY - 2]];
    for (let k = 0; k < 3; k++) {
      const [x, y] = flying[(i + k) % 5];
      p.px(x, y, k === 0 ? 'e' : 'E');
      p.px(x + 1, y, 'e');
    }
    for (let x = 0; x < 24; x++) p.px(x, GY, 'l');
    for (let x = 35; x < W; x++) p.px(x, GY, 'l');
    for (let x = 0; x < 24; x++) if ((x + i) % 7 === 0) p.px(x, GY + 1, 'l');
    if (i >= 9) {
      const up = i === 9 ? 0 : i === 10 ? 3 : 5;
      p.stamp(28, GY - up - 1, ['.xx.', 'xxxX', 'xXXX']);
      p.rect(26, GY, 8, 1, 'E');
      if (i >= 10) (p.px(26, GY - 7, 's'), p.px(33, GY - 8, 's'), p.px(34, GY - 5, 's'));
    }
    frames.push(p.frame());
  }
  return frames;
}

// --------------------------------------------------------------------------------------------------------------------- sit

/** Perched on a branch, puffed up, cooing: a heart for each coo. */
function sit(): Frame[] {
  const frames: Frame[] = [];
  const beats: Array<{ puff: number; heart: number; blink: boolean; bob: number }> = [
    { puff: 0, heart: 0, blink: false, bob: 0 }, { puff: 1, heart: 1, blink: false, bob: 1 }, { puff: 1, heart: 2, blink: false, bob: 0 },
    { puff: 0, heart: 3, blink: true, bob: 1 }, { puff: 0, heart: 4, blink: false, bob: 0 }, { puff: 1, heart: 0, blink: false, bob: 1 },
  ];
  for (const { puff, heart, blink, bob } of beats) {
    const p = new Pix();
    // the branch
    p.rect(2, 17, 28, 2, 'e');
    p.rect(2, 18, 28, 1, 'E');
    p.rect(24, 15, 2, 2, 'e');
    // a plump body leaning back, tail down behind
    p.rect(5, 11, 5, 6, 'd', true);
    p.oval(14, 11, 7.5 + puff * 0.5, 6 + puff * 0.5, 'f');
    p.oval(19, 12, 4.5, 4.5, 'c');
    p.oval(13, 11, 5, 3.5, 'd');
    p.rect(9, 12, 8, 1, 'f');
    // neck and head, a little higher than when walking
    p.oval(21, 8 + bob, 3.4, 4, 'f');
    p.oval(23, 5 + bob, 3.4, 3, 'f');
    p.rect(19, 7 + bob, 3, 2, 'M');
    p.rect(21, 8 + bob, 2, 2, 'N');
    p.rect(26, 5 + bob, 3, 2, 'y');
    p.px(26, 5 + bob, 'c');
    if (blink) p.rect(23, 4 + bob, 2, 1, 'n');
    else (p.px(24, 4 + bob, 'n'), p.px(23, 4 + bob, 'u'));
    // feet on the branch
    p.line(13, 17, 13, 16, 'p');
    p.line(17, 17, 17, 16, 'p');
    p.rect(12, 16, 3, 1, 'p');
    p.rect(16, 16, 3, 1, 'p');
    p.outline();
    if (heart > 0) p.stamp(29, 3 - Math.min(heart - 1, 2), HEART);
    frames.push(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ sleep

function sleep(): Frame[] {
  const make = (breath: number, zs: number): Frame => {
    const p = new Pix();
    // a feathered ball, its head turned back and tucked in
    p.rect(4, 12, 6, 4, 'd', true);
    p.oval(17, 13 - breath * 0.5, 10, 6 + breath * 0.5, 'f');
    p.oval(21, 15, 6, 3, 'c');
    p.oval(16, 12 - breath * 0.5, 7, 4, 'd');
    p.rect(10, 12, 12, 1, 'f');
    p.oval(24, 9, 3.4, 3, 'f');
    p.rect(21, 11, 3, 2, 'M');
    p.rect(25, 8, 3, 2, 'y');
    p.rect(22, 8, 2, 1, 'n'); // closed eye
    // one foot showing
    p.line(15, 18, 15, 19, 'p');
    p.rect(14, 19, 3, 1, 'p');
    p.outline();
    ground(p);
    if (zs > 0) p.stamp(28, 4 - (zs - 1) * 2 + 1, Z);
    if (zs > 1) p.px(25, 5 - zs + 3, 'z');
    return p.frame();
  };
  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ lick

const LY = 2;

/** Face to the glass, tapping at it with its beak. */
function lick(): Frame[] {
  const frames: Frame[] = [];
  const sweep: Array<[number, number]> = [[16, 1], [14, 3], [11, 4], [9, 4], [12, 4], [15, 4], [18, 4], [21, 4], [24, 3], [18, 2], [16, 1], [16, 0]];
  const taps: Array<[number, number]> = [];
  sweep.forEach(([tx, len], i) => {
    const p = new Pix();
    const shift = Math.round((tx - 16) / 4); // the head follows the pecking
    const Q = (x: number, y: number, c: string) => p.px(x + shift, y + LY, c);
    const O = (cx: number, cy: number, rx: number, ry: number, c: string) => p.oval(cx + shift, cy + LY, rx, ry, c);
    const R = (x: number, y: number, w: number, h: number, c: string, round = false) => p.rect(x + shift, y + LY, w, h, c, round);
    // the neck's sheen below, the round head, and the eyes with their orange rings
    O(18, 15, 8, 2.4, 'f');
    R(10, 13, 6, 3, 'M');
    R(20, 13, 6, 3, 'N');
    R(15, 14, 6, 2, 'M');
    O(18, 9, 9, 7.5, 'f');
    O(18, 12, 6, 4, 'c');
    O(12, 8, 2.4, 2.4, 'u');
    O(24, 8, 2.4, 2.4, 'u');
    R(12, 7, 2, 3, 'n');
    R(22, 7, 2, 3, 'n');
    Q(12, 7, 'w');
    Q(22, 7, 'w');
    // the beak, pushed out as it taps
    R(16, 10 + (len > 2 ? 1 : 0), 4, 3, 'y');
    R(16, 10 + (len > 2 ? 1 : 0), 4, 1, 'c');
    Q(17, 12 + (len > 2 ? 1 : 0), 'n');
    p.outline();
    // where it has tapped, marks on the glass
    if (len >= 3) taps.push([tx, 14]);
    taps.slice(-4).forEach(([x, y], k, a) => {
      p.px(x + shift, y + LY + 2, k === a.length - 1 ? 'q' : 'g');
      p.px(x + shift + 1, y + LY + 3, k === a.length - 1 ? 'q' : 'g');
    });
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    if (len === 4 && i % 3 === 0) p.px(31, 4, 's');
    frames.push(p.frame());
  });
  return frames;
}

export function pigeonScene(scene: Scene): Frame[] {
  return { run, sniff, dig, sit, sleep, lick }[scene]();
}
