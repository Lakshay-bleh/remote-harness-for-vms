/**
 * The pixel toolkit every animal is drawn with: a grid of characters (one per pixel), a few shapes, and an automatic outline. Nothing
 * here touches the screen.
 */

export type Frame = string[];

export const W = 36;
export const H = 22;
export const GROUND_Y = 20;

/** The characters that belong to the animal itself: only these get an outline. */
export const BODY = new Set(['f', 'd', 'c', 'n', 't', 'T', 'w', 'M', 'N', 'H', 'p', 'y', 'u', 'j', 'x']);

export class Pix {
  readonly w: number;
  readonly h: number;
  readonly cells: string[][];
  constructor(w: number = W, h: number = H) {
    this.w = w;
    this.h = h;
    this.cells = Array.from({ length: h }, () => Array<string>(w).fill('.'));
  }
  px(x: number, y: number, c: string): this {
    x = Math.round(x);
    y = Math.round(y);
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
  /** A filled ellipse around a centre, for round bodies. */
  oval(cx: number, cy: number, rx: number, ry: number, c: string): this {
    for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
      for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
        const dx = (x - cx) / (rx + 0.35);
        const dy = (y - cy) / (ry + 0.35);
        if (dx * dx + dy * dy <= 1) this.px(x, y, c);
      }
    return this;
  }
  /** A line of single pixels. */
  line(x0: number, y0: number, x1: number, y1: number, c: string): this {
    const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1);
    for (let i = 0; i <= steps; i++) this.px(x0 + ((x1 - x0) * i) / steps, y0 + ((y1 - y0) * i) / steps, c);
    return this;
  }
  /** A limb: 2x2 squares along the points, so a leg can lean and bend. */
  limb(points: Array<[number, number]>, c: string, paw = 'c'): this {
    points.forEach(([x, y], i) => this.rect(x, y, 2, 2, i === points.length - 1 ? paw : c));
    return this;
  }
  /** Put a 1-pixel outline around the animal's own colours. */
  outline(): this {
    const mark: Array<[number, number]> = [];
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) {
        if (this.cells[y][x] !== '.') continue;
        const near = [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].some(([a, b]) => BODY.has(this.cells[b]?.[a] ?? '.'));
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

/** Where a scene is drawn: positions are in the scene's own coordinates, shifted to the standard place on the picture. */
export interface Brush {
  R(x: number, y: number, w: number, h: number, c: string, round?: boolean): void;
  P(x: number, y: number, c: string): void;
}

export type View = 'side' | 'sit' | 'sleep' | 'dig' | 'front';

/**
 * What makes one four-legged animal different from another, as a few hooks into the shared drawing. A hook that is missing leaves
 * the dog's own part in place. Coordinates are those of the dog's part in the same scene, so a species draws relative to them.
 */
export interface Skin {
  /** Replaces the floppy ear. `x, y` is where the dog's ear starts; `blown` when the wind has it back (running). For the front view `side` says which ear. */
  ear?(b: Brush, view: View, x: number, y: number, o: { blown?: boolean; side?: 'left' | 'right' }): void;
  /** Replaces the tail path with the cells to draw (x, y, colour). */
  tail?(path: Array<[number, number]>, view: View): Array<[number, number, string]>;
  /** Extras on the head: `x, y, w, h` is the head's box. */
  head?(b: Brush, view: View, x: number, y: number, w: number, h: number): void;
  /** Extras on the muzzle (whiskers, a trunk): `x, y` is the 4x4 muzzle's top left. */
  snout?(b: Brush, view: View, x: number, y: number): void;
  /** Extras on the body, drawn after it: a mane, stripes. `x, y, w, h` is the main body box. */
  body?(b: Brush, view: View, x: number, y: number, w: number, h: number): void;
}
