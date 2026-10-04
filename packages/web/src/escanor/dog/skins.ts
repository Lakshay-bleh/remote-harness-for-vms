/**
 * The four-legged companions that share the dog's skeleton: what differs is the ears, tail, snout and a few extras, drawn through the
 * hooks in `Skin`. (The hamster and the pigeon are built differently and have their own files.)
 */
import type { Brush, Skin, View } from './pix.ts';

type Cell = [number, number, string];

/** Whether a tail path is held up (rising from its root) or low and flat along the ground. */
const rising = (path: Array<[number, number]>) => path[path.length - 1][1] < path[0][1];

/** The head's top-left corner, from where the dog's ear starts: the ears of the other animals sit on top of the head. */
function headOrigin(view: View, x: number, y: number, blown?: boolean): { hx: number; ht: number; w: number } {
  switch (view) {
    case 'side': return { hx: 19, ht: blown ? y : y - 1, w: 7 };
    case 'sit': return { hx: x + 1, ht: y - 1, w: 8 };
    case 'sleep': return { hx: x + 2, ht: y, w: 7 };
    case 'dig': return { hx: x + 1, ht: y, w: 7 };
    default: return { hx: x, ht: y, w: 7 };
  }
}

// ------------------------------------------------------------------------------------------------------------------- cat

/** A pointed ear standing on the head: three rows tall, a pink inside. `lean` tips it back (running into the wind). */
function pointEar(b: Brush, tx: number, ht: number, lean: -1 | 0 = 0, tall = true): void {
  b.R(tx, ht - 1, 3, 2, 'f');
  b.P(tx + 1, ht - 1, 't');
  if (!tall) return;
  b.R(tx + lean, ht - 2, 3, 1, 'f');
  b.P(tx + 1 + lean * 2, ht - 3, 'f');
  if (lean) b.P(tx + lean * 3, ht - 2, 'f');
  b.P(tx + 1 + lean, ht - 2, 't');
}

export const catSkin: Skin = {
  ear(b, view, x, y, o) {
    if (view === 'front') {
      // the two ears on the corners of the face, pointing up
      const left = o.side === 'left';
      const tx = left ? 9 : 22;
      b.R(tx + 1, 0, 3, 1, 'f');
      b.R(tx, 1, 5, 2, 'f');
      b.R(tx + 1, 1, 3, 1, 't');
      return;
    }
    const { hx, ht } = headOrigin(view, x, y, o.blown);
    pointEar(b, hx + 1, ht, o.blown ? -1 : 0, view !== 'sit');
    pointEar(b, hx + 4, ht, o.blown ? -1 : 0, view !== 'sit');
  },
  tail(path, view) {
    const last = path[path.length - 1];
    const cells: Cell[] = path.map(([x, y]) => [x, y, 'f']);
    if (view === 'sleep') return cells.map(([x, y, c], i): Cell => [x, y, i === cells.length - 1 ? 'd' : c]);
    const extra: Array<[number, number]> = view === 'dig' ? [] : rising(path) ? [[last[0], last[1] - 1], [last[0] + 1, last[1] - 2], [last[0] + 2, last[1] - 2]] : [[last[0] - 1, last[1]], [last[0] - 2, last[1] - 1], [last[0] - 2, last[1] - 2]];
    extra.forEach(([x, y]) => cells.push([x, y, 'f']));
    cells[cells.length - 1][2] = 'd';
    cells[cells.length - 2][2] = 'd';
    return cells;
  },
  snout(b, view, x, y) {
    if (view === 'front') {
      for (const [dx, dy] of [[-4, 3], [-3, 2], [-4, 5], [-2, 4]] as const) b.P(x + dx, y + dy, 'w');
      for (const [dx, dy] of [[11, 3], [12, 2], [13, 5], [12, 4]] as const) b.P(x + dx, y + dy, 'w');
      return;
    }
    b.P(x + 4, y + 1, 'w');
    b.P(x + 5, y + 2, 'w');
    b.P(x + 4, y + 3, 'w');
  },
  body(b, view, x, y, w, h) {
    // tabby stripes down the back
    const n = view === 'side' ? 4 : view === 'dig' ? 3 : 2;
    for (let i = 0; i < n; i++) b.R(x + 2 + i * Math.max(2, Math.floor((w - 3) / n)), y, 1, Math.min(2, h), 'd');
  },
};

// --------------------------------------------------------------------------------------------------------------- unicorn

/** The horn: gold with a bright edge, leaning forward from the forehead. */
function horn(b: Brush, bx: number, by: number, tall = true): void {
  b.R(bx, by - 1, 2, 2, 'H');
  if (tall) (b.R(bx, by - 2, 2, 1, 'H'), b.P(bx + 1, by - 3, 'H'));
  if (tall) b.P(bx, by - 2, 'w');
}

export const unicornSkin: Skin = {
  ear(b, view, x, y, o) {
    if (view === 'front') {
      const left = o.side === 'left';
      const tx = left ? 9 : 23;
      b.R(tx, 0, 4, 4, 'f', true);
      b.P(tx + 1 + (left ? 0 : 1), 1, 't');
      b.P(tx + 1 + (left ? 0 : 1), 2, 't');
      return;
    }
    const { hx, ht } = headOrigin(view, x, y, o.blown);
    // a small ear beside the horn
    if (view === 'sit') b.R(hx + 1, ht - 1, 2, 2, 'f');
    else b.R(hx + 1, ht - 2, 2, 3, 'f');
    b.P(hx + 1, ht - 1, 't');
  },
  head(b, view, x, y, w) {
    if (view === 'front') {
      horn(b, x + w / 2 - 1, y + 1);
      // the forelock falls over the forehead, in the mane's colours
      b.R(x + 2, y + 1, 3, 4, 'M', true);
      b.R(x + w - 5, y + 1, 3, 4, 'N', true);
      b.P(x + 3, y + 3, 'N');
      b.P(x + w - 4, y + 3, 'M');
      return;
    }
    horn(b, x + w - 3, y, view !== 'sit');
    // the mane runs down the back of the neck
    for (let i = 0; i < Math.min(8, 17 - y); i++) {
      b.R(x - 2, y + 1 + i, 2, 1, i % 2 ? 'N' : 'M');
      if (i < 5) b.P(x + 1, y + 1 + i, i % 2 ? 'M' : 'N');
    }
    b.P(x + w - 2, y + 1, 'M');
  },
  tail(path, view) {
    const cells: Cell[] = [];
    path.forEach(([x, y], i) => {
      cells.push([x, y, i % 2 ? 'N' : 'M']);
      cells.push([view === 'sleep' ? x : x + 1, view === 'sleep' ? y + 1 : y, i % 2 ? 'M' : 'N']);
    });
    const last = path[path.length - 1];
    if (view !== 'dig') cells.push([last[0], last[1] - 1, 'M']);
    return cells;
  },
};

// -------------------------------------------------------------------------------------------------------------- elephant

export const elephantSkin: Skin = {
  ear(b, view, x, y, o) {
    if (view === 'front') {
      const left = o.side === 'left';
      b.R(left ? 2 : 26, 1, 8, 12, 'd', true);
      b.R(left ? 3 : 27, 3, 5, 8, 'f', true);
      return;
    }
    // one big ear, flapping back from the head
    const lift = o.blown ? -2 : 0;
    const eh = Math.min(9, 19 - y);
    b.R(x - 3, y - 1 + lift, 7, eh, 'd', true);
    b.R(x - 2, y + lift, 4, Math.max(2, eh - 3), 'c', true);
  },
  snout(b, view, x, y) {
    if (view === 'front') {
      b.R(x + 2, y - 1, 6, 9, 'f', true);
      for (let r = 0; r < 3; r++) b.R(x + 3, y + r * 3 + 1, 4, 1, 'd');
      return;
    }
    // the trunk: out from the muzzle and curling down
    const pts: Array<[number, number]> = view === 'sit' ? [[1, 1], [2, 3], [2, 5], [1, 7], [0, 8]] : [[1, 1], [3, 2], [4, 4], [4, 6], [3, 8]];
    const reach = pts.filter(([, dy]) => !(view === 'side' || view === 'sleep') || y + dy <= 16);
    reach.forEach(([dx, dy], i) => b.R(x + dx, y + dy, 2, 2, i === reach.length - 1 ? 'c' : i % 2 ? 'f' : 'd'));
    // a small white tusk
    b.P(x + 1, y + 3, 'w');
  },
  tail(path, view) {
    if (view === 'sleep') return path.slice(0, 3).map(([x, y], i): Cell => [x, y, i === 2 ? 'd' : 'f']);
    const cells: Cell[] = path.slice(0, 3).map(([x, y]) => [x, y, 'f']);
    const last = path[Math.min(2, path.length - 1)];
    cells.push([last[0], last[1] + 1, 'd']);
    return cells;
  },
};
