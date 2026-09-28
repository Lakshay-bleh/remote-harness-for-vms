// Zero-dependency PNG icon generator. Draws a simple "terminal prompt" mark
// (a chevron + cursor) on a dark rounded-square background, procedurally,
// and writes it as a real PNG using only Node's built-in zlib for deflate.
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Escanor-derived palette: a coral mark on a dark-ink "product chrome" ground,
// echoing the cream/dark contrast rhythm used for code + technical surfaces.
const BG_TOP = [37, 35, 32]; // surface-dark-elevated #252320
const BG_BOTTOM = [24, 23, 21]; // surface-dark #181715
const ACCENT = [204, 120, 92]; // primary (coral) #cc785c

function crc32(buf) {
  let c;
  const table = crc32.table ?? (crc32.table = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })());
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function distToSegment(px, py, ax, ay, bx, by) {
  const abx = bx - ax;
  const aby = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * abx + (py - ay) * aby) / (abx * abx + aby * aby)));
  const cx = ax + t * abx;
  const cy = ay + t * aby;
  return Math.hypot(px - cx, py - cy);
}

function roundedSquareMask(x, y, size, radius) {
  const cx = Math.min(Math.max(x, radius), size - radius);
  const cy = Math.min(Math.max(y, radius), size - radius);
  return Math.hypot(x - cx, y - cy) <= radius;
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function renderIcon(size) {
  const radius = size * 0.22;
  const strokeWidth = size * 0.075;
  const data = Buffer.alloc(size * size * 4);

  // chevron ">" as two line segments, plus a cursor bar, in a centered box
  const bx = size * 0.32;
  const by = size * 0.30;
  const mx = size * 0.5;
  const my = size * 0.5;
  const ex = size * 0.32;
  const ey = size * 0.70;
  const cursorX = size * 0.56;
  const cursorTop = size * 0.62;
  const cursorBottom = size * 0.76;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      if (!roundedSquareMask(x + 0.5, y + 0.5, size, radius)) {
        data[i] = 0;
        data[i + 1] = 0;
        data[i + 2] = 0;
        data[i + 3] = 0;
        continue;
      }
      const t = y / size;
      let r = lerp(BG_TOP[0], BG_BOTTOM[0], t);
      let g = lerp(BG_TOP[1], BG_BOTTOM[1], t);
      let b = lerp(BG_TOP[2], BG_BOTTOM[2], t);

      const dChevron = Math.min(
        distToSegment(x, y, bx, by, mx, my),
        distToSegment(x, y, mx, my, ex, ey),
      );
      const dCursor = distToSegment(x, y, cursorX, cursorTop, cursorX, cursorBottom);
      const d = Math.min(dChevron, dCursor - strokeWidth * 0.1);

      const edge = strokeWidth / 2;
      if (d < edge) {
        const mix = Math.max(0, Math.min(1, edge - d));
        r = lerp(r, ACCENT[0], mix);
        g = lerp(g, ACCENT[1], mix);
        b = lerp(b, ACCENT[2], mix);
      }

      data[i] = Math.round(r);
      data[i + 1] = Math.round(g);
      data[i + 2] = Math.round(b);
      data[i + 3] = 255;
    }
  }
  return data;
}

function encodePng(size) {
  const raw = renderIcon(size);
  const stride = size * 4;
  const withFilters = Buffer.alloc((stride + 1) * size);
  for (let y = 0; y < size; y++) {
    withFilters[y * (stride + 1)] = 0;
    raw.copy(withFilters, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const idat = deflateSync(withFilters);
  return Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const outDir = resolve(process.argv[2] || 'packages/web/public');
for (const size of [192, 512]) {
  const png = encodePng(size);
  writeFileSync(resolve(outDir, `icon-${size}.png`), png);
  console.log(`wrote icon-${size}.png (${png.length} bytes)`);
}
