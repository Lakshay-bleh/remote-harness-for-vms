/**
 * What only the four-legged companions do beyond the shared scenes:
 *  - `react`: what happens when you tap one. Each answers in its own way (the dog spins round, the unicorn prances under a rainbow,
 *    the cat arches and pounces, the elephant raises its trunk and sprays).
 *  - `home`: each in its own place, with the things it likes (the dog's kennel and bone, the unicorn's cloud and rainbow, the cat's box
 *    and yarn, the elephant's pool and palm).
 * The hamster and the pigeon have theirs in their own files.
 */
import type { Animal } from './animals.ts';
import { GROUND_Y, H, Pix, W, type Frame, type Skin } from './pix.ts';
import { ground, sideDog, sit, type Side } from './sprites.ts';

/** Points of a ring (angles in degrees, 0 = right, 90 = down). */
function ring(p: Pix, cx: number, cy: number, r: number, from: number, to: number, c: string): void {
  for (let a = from; a <= to; a += 4) p.px(cx + Math.cos((a * Math.PI) / 180) * r, cy + Math.sin((a * Math.PI) / 180) * r, c);
}

/** A little four-point star. */
function twinkle(p: Pix, x: number, y: number, big: boolean): void {
  p.px(x, y, 's');
  if (big) (p.px(x - 1, y, 's'), p.px(x + 1, y, 's'), p.px(x, y - 1, 's'), p.px(x, y + 1, 's'));
}

/** Keep decorations on the picture and off its outermost pixels, so nothing is cut off. */
const inside = (x: number, y: number) => x >= 2 && x <= W - 3 && y >= 2 && y <= H - 3;

// ------------------------------------------------------------------------------------------------------------------ react

interface Turn {
  mirror: boolean;
  lift: number;
  legs: Side['legs'];
  tail: Side['tail'];
}

/** The dog spins on the spot: it faces one way, then the other, hopping, with dust at its feet and stars going round its head. */
function dogReact(sk: Skin): Frame[] {
  const turns: Turn[] = [
    { mirror: false, lift: 0, legs: 'stand', tail: 'up' },
    { mirror: false, lift: 3, legs: 'runA', tail: 'mid' },
    { mirror: true, lift: 4, legs: 'runB', tail: 'up' },
    { mirror: true, lift: 1, legs: 'stand', tail: 'mid' },
    { mirror: false, lift: 3, legs: 'runB', tail: 'up' },
    { mirror: true, lift: 4, legs: 'runA', tail: 'mid' },
    { mirror: false, lift: 2, legs: 'runA', tail: 'up' },
    { mirror: true, lift: 0, legs: 'stand', tail: 'up' },
  ];
  return turns.map((t, i) => {
    const p = new Pix();
    sideDog(p, { legs: t.legs, lift: t.lift, tail: t.tail, mouth: 'pant', ears: t.lift > 1 ? 'back' : 'down', head: 0 }, sk, 2, 0);
    p.outline();
    if (t.mirror) p.mirror();
    ground(p, i);
    // the dust it kicks up, circling its feet
    for (let k = 0; k < 4; k++) {
      const a = (i * 50 + k * 90) * (Math.PI / 180);
      p.px(18 + Math.cos(a) * (9 + (k % 2)), GROUND_Y - 1 - Math.abs(Math.sin(a)) * 2, 'g');
    }
    // stars going round
    for (let k = 0; k < 3; k++) {
      const a = (i * 45 + k * 120) * (Math.PI / 180);
      const x = Math.round(18 + Math.cos(a) * 12);
      const y = Math.round(6 + Math.sin(a) * 3);
      if (inside(x, y)) twinkle(p, x, y, k === 0);
    }
    return p.frame();
  });
}

/** The unicorn prances under a rainbow that builds up as it goes, with sparkles round its horn. */
function unicornReact(sk: Skin): Frame[] {
  const bands = ['M', 'H', 'G', 'N'];
  return Array.from({ length: 8 }, (_, i) => {
    const p = new Pix();
    const shown = Math.min(bands.length, 1 + Math.floor(i / 2));
    for (let b = 0; b < shown; b++) ring(p, 18, 22, 14 - b, 196, 344, bands[b]);
    const prance: Array<Side['legs']> = ['runA', 'runB', 'runA', 'runB', 'runA', 'runB', 'stand', 'runA'];
    sideDog(p, { legs: prance[i], lift: i % 2 ? 1 : 0, tail: i % 2 ? 'up' : 'mid', mouth: 'pant', ears: 'back', head: 0 }, sk, 0, 0);
    p.outline();
    ground(p, i);
    for (const [x, y] of [[8, 5], [29, 4], [24, 9], [5, 11]] as const) if ((i + x) % 3 !== 0) twinkle(p, x, y, (i + y) % 2 === 0);
    return p.frame();
  });
}

/** The cat arches its back, crouches and pounces, and says so, with its tail puffed up. */
function catReact(sk: Skin): Frame[] {
  const poses: Array<{ legs: Side['legs']; head: number; tail: Side['tail']; lift: number }> = [
    { legs: 'stand', head: 0, tail: 'up', lift: 0 },
    { legs: 'stand', head: 0, tail: 'up', lift: 1 },
    { legs: 'stand', head: 4, tail: 'mid', lift: 0 },
    { legs: 'walkA', head: 7, tail: 'low', lift: 0 },
    { legs: 'runA', head: 0, tail: 'up', lift: 1 },
    { legs: 'runB', head: 0, tail: 'mid', lift: 1 },
    { legs: 'stand', head: 0, tail: 'up', lift: 1 },
    { legs: 'stand', head: 0, tail: 'up', lift: 0 },
  ];
  return poses.map((o, i) => {
    const p = new Pix();
    sideDog(p, { ...o, mouth: o.head < 5 ? 'pant' : 'closed', ears: o.head >= 4 ? 'back' : 'down' }, sk, 0, 0);
    // the arched back: a hump over the body when it is not crouching
    if (o.head < 4) p.rect(12, 7 - o.lift, 8, 2, 'f', true);
    p.outline();
    ground(p, i);
    // "!" over its head, and the wiggle of excitement
    if (i % 2 === 0) p.stamp(30, 3, ['h', 'h', 'h', '.', 'h']);
    if (i % 3 === 1) (p.px(5, 8, 'g'), p.px(3, 10, 'g'));
    return p.frame();
  });
}

/** The elephant: trunk up in a trumpet, ears flapping, a fountain of water from the tip. */
const elephantUp: Skin = {
  ear: (b, view, x, y, o) => {
    if (view !== 'side') return;
    const lift = o.blown ? -2 : 0;
    b.R(x - 3, y - 1 + lift, 7, 9, 'd', true);
    b.R(x - 2, y + lift, 4, 6, 'c', true);
  },
  snout(b, view, x, y) {
    if (view !== 'side') return;
    // out, then straight up
    const pts: Array<[number, number]> = [[1, 0], [3, -1], [4, -3], [4, -5], [3, -7]];
    pts.forEach(([dx, dy], i) => b.R(x + dx, y + dy, 2, 2, i === pts.length - 1 ? 'c' : i % 2 ? 'f' : 'd'));
    b.P(x + 1, y + 3, 'w');
  },
  tail: elephantTail,
};
function elephantTail(path: Array<[number, number]>): Array<[number, number, string]> {
  const cells = path.slice(0, 3).map(([x, y]): [number, number, string] => [x, y, 'f']);
  const last = path[Math.min(2, path.length - 1)];
  cells.push([last[0], last[1] + 1, 'd']);
  return cells;
}

function elephantReact(base: Skin): Frame[] {
  const sk: Skin = { ...base, ...elephantUp };
  return Array.from({ length: 8 }, (_, i) => {
    const p = new Pix();
    const legs: Array<Side['legs']> = ['stand', 'walkA', 'stand', 'walkB', 'stand', 'walkA', 'stand', 'walkB'];
    // the ear flaps through `blown`; the trunk sway is the 2px shift of the whole animal
    sideDog(p, { legs: legs[i], lift: 0, tail: i % 2 ? 'mid' : 'up', mouth: 'closed', ears: i % 2 ? 'back' : 'down', head: 0 }, sk, i % 2 ? 0 : -1, 0);
    p.outline();
    ground(p, i);
    // water thrown from the tip: drops on an arc, raining down
    const tipX = 31 + (i % 2);
    for (let k = 0; k < 5; k++) {
      const t = ((i + k * 2) % 8) / 8;
      const x = Math.round(tipX + (t - 0.3) * 8 * (k % 2 ? 1 : -0.4) + (k - 2));
      const y = Math.round(2 + t * t * 14);
      if (inside(x, y)) p.px(x, y, k % 2 ? 'a' : 'q');
    }
    return p.frame();
  });
}

export function quadReact(animal: Animal, sk: Skin): Frame[] {
  switch (animal) {
    case 'unicorn': return unicornReact(sk);
    case 'cat': return catReact(sk);
    case 'elephant': return elephantReact(sk);
    default: return dogReact(sk);
  }
}

// ------------------------------------------------------------------------------------------------------------------- home

const KENNEL = [
  '....R....',
  '...RRR...',
  '..RRRRR..',
  '.RRRRRRR.',
  'RRRRRRRRR',
  '.WWWWWWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
];

/** The dog by its kennel, with a bone to chew and a ball. */
function dogHome(sk: Skin): Frame[] {
  return sit(sk, {
    dx: -2,
    back(p) {
      p.stamp(26, 10, KENNEL);
      p.rect(28, 12, 5, 1, 'r'); // a name board over the door
    },
    front(p, i) {
      p.stamp(23, 18, ['b..b', 'bbbb', 'B..B'].slice(0, 2));
      p.rect(23, 19, 4, 1, 'B');
      if (i % 2) p.px(25, 17, 's');
    },
  });
}

/** The unicorn on a cloud, in front of a rainbow, under twinkling stars. */
function unicornHome(sk: Skin): Frame[] {
  return sit(sk, {
    dx: -2,
    ground: false,
    back(p, i) {
      ['M', 'H', 'G', 'N'].forEach((c, b) => ring(p, 23, 19, 10 - b, 180, 360, c));
      for (const [x, y] of [[4, 4], [11, 2], [33, 3], [30, 12]] as const) if ((i + x) % 3 !== 0) twinkle(p, x, y, (i + x) % 2 === 0);
    },
    front(p) {
      // the cloud it sits on, over its hooves
      for (let x = 0; x < W; x++) {
        const h = 1 + ((x * 7) % 5 < 2 ? 1 : 0);
        for (let y = GROUND_Y - h; y <= GROUND_Y; y++) p.px(x, y, y === GROUND_Y ? 'g' : 'w');
      }
      p.rect(0, GROUND_Y + 1, W, 1, 'g');
    },
  });
}

/** The cat by its box, with a ball of yarn that it has unrolled across the floor. */
function catHome(sk: Skin): Frame[] {
  return sit(sk, {
    dx: -2,
    back(p, i) {
      // the box, its flaps open
      p.rect(25, 12, 10, 8, 'W');
      p.rect(25, 12, 10, 1, 'm');
      p.rect(26, 14, 8, 5, 'm');
      p.rect(24, 10, 4, 2, 'W');
      p.rect(32, 10, 4, 2, 'W');
      p.px(i % 2 ? 29 : 30, 13, 'f'); // ears of something in the box, watching
      p.px(i % 2 ? 31 : 30, 13, 'f');
    },
    front(p, i) {
      const x = 22 + (i % 3);
      p.oval(x, GROUND_Y - 2, 2, 2, 'S');
      p.px(x - 1, GROUND_Y - 3, 'w');
      for (let k = 0; k < 7; k++) p.px(x + 2 + k * 0.5, GROUND_Y - 1 + (k % 2 ? 0 : -0.4), 'S'); // the thread
    },
  });
}

/** The elephant by a small pool, under a palm, with a peanut. */
function elephantHome(sk: Skin): Frame[] {
  return sit(sk, {
    dx: -2,
    back(p) {
      // a palm: trunk and fronds
      for (let y = 8; y < GROUND_Y; y++) p.px(32 + (y % 4 === 0 ? 0 : 1), y, 'm');
      for (const [x, y] of [[29, 6], [30, 5], [31, 5], [33, 5], [34, 5], [35, 6], [30, 7], [34, 7]] as const) p.px(x, y, (x + y) % 2 ? 'G' : 'Y');
      p.rect(31, 6, 4, 1, 'G');
    },
    front(p, i) {
      // the pool in front of its feet, and a drop falling into it
      for (let x = 14; x < 31; x++) for (let y = GROUND_Y - 1; y <= GROUND_Y; y++) p.px(x, y, (x + i + y) % 5 === 0 ? 'a' : 'A');
      const dropY = 12 + ((i * 3) % 7);
      p.px(22, dropY, 'a');
      p.px(22, dropY - 1, 'q');
      p.px(31, GROUND_Y - 2, 'Q'); // a peanut
      p.px(32, GROUND_Y - 2, 'Q');
    },
  });
}

export function quadHome(animal: Animal, sk: Skin): Frame[] {
  switch (animal) {
    case 'unicorn': return unicornHome(sk);
    case 'cat': return catHome(sk);
    case 'elephant': return elephantHome(sk);
    default: return dogHome(sk);
  }
}
