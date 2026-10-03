import jsQR from 'jsqr';

/**
 * Read a QR code out of one camera frame (RGBA pixels). This is plain JavaScript on purpose: Android's WebView has no
 * `BarcodeDetector`, which is what the scanner used before, so on the phone it never found anything.
 *
 * Both polarities are tried, so a code shown light-on-dark (a dark-mode screen, or a mirrored one) reads too.
 */
export function decodeQr(rgba: Uint8ClampedArray, width: number, height: number): string | null {
  return jsQR(rgba, width, height, { inversionAttempts: 'attemptBoth' })?.data ?? null;
}

const luma = (rgba: Uint8ClampedArray, i: number) => (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) / 1000;

function grey(values: Float32Array | Uint8ClampedArray, w: number, h: number, pick: (i: number) => number): Uint8ClampedArray {
  const out = new Uint8ClampedArray(w * h * 4);
  for (let p = 0; p < w * h; p++) {
    const v = pick(p);
    out[p * 4] = out[p * 4 + 1] = out[p * 4 + 2] = v;
    out[p * 4 + 3] = 255;
  }
  return out;
}

/**
 * Stretch a dim or washed-out frame to the full range: the darkest 2% becomes black and the lightest 2% white. A code seen in poor
 * light often differs from its background by only a few shades, which is too little for the plain decoder.
 */
export function stretchContrast(rgba: Uint8ClampedArray, width: number, height: number): Uint8ClampedArray {
  const n = width * height;
  const hist = new Uint32Array(256);
  for (let p = 0; p < n; p++) hist[Math.round(luma(rgba, p * 4))]++;
  const cut = n * 0.02;
  let lo = 0;
  let hi = 255;
  for (let acc = 0; lo < 255 && (acc += hist[lo]) < cut; lo++);
  for (let acc = 0; hi > 0 && (acc += hist[hi]) < cut; hi--);
  const span = Math.max(24, hi - lo);
  return grey(rgba, width, height, (p) => ((luma(rgba, p * 4) - lo) / span) * 255);
}

/**
 * Black or white for each pixel against the average of the area around it, not of the whole frame. That is what copes with a shadow
 * across the screen, glare on one side, or a camera that exposes for the brightest part: the same code is "dark" in one corner and
 * "light" in another.
 */
export function localThreshold(rgba: Uint8ClampedArray, width: number, height: number): Uint8ClampedArray {
  const w = width + 1;
  const sum = new Float64Array(w * (height + 1));
  for (let y = 0; y < height; y++) {
    let row = 0;
    for (let x = 0; x < width; x++) {
      row += luma(rgba, (y * width + x) * 4);
      sum[(y + 1) * w + x + 1] = sum[y * w + x + 1] + row;
    }
  }
  const r = Math.max(8, Math.round(Math.min(width, height) / 16));
  return grey(rgba, width, height, (p) => {
    const x = p % width;
    const y = (p / width) | 0;
    const x0 = Math.max(0, x - r), x1 = Math.min(width, x + r + 1), y0 = Math.max(0, y - r), y1 = Math.min(height, y + r + 1);
    const area = (x1 - x0) * (y1 - y0);
    const mean = (sum[y1 * w + x1] - sum[y0 * w + x1] - sum[y1 * w + x0] + sum[y0 * w + x0]) / area;
    return luma(rgba, p * 4) < mean * 0.92 ? 0 : 255;
  });
}

/** Everything that helps in poor conditions, cheapest first: as it is, with the contrast stretched, then judged area by area. */
export function decodeQrHard(rgba: Uint8ClampedArray, width: number, height: number): string | null {
  return decodeQr(rgba, width, height) ?? decodeQr(stretchContrast(rgba, width, height), width, height) ?? decodeQr(localThreshold(rgba, width, height), width, height);
}

/** The middle of a frame, cropped (the code is held in the aiming box, and the rest is only noise to the decoder). */
export function centreCrop(rgba: Uint8ClampedArray, width: number, height: number, fraction = 0.7): { data: Uint8ClampedArray; width: number; height: number } {
  const w = Math.max(1, Math.round(width * fraction));
  const h = Math.max(1, Math.round(height * fraction));
  const x0 = Math.floor((width - w) / 2);
  const y0 = Math.floor((height - h) / 2);
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) data.set(rgba.subarray(((y0 + y) * width + x0) * 4, ((y0 + y) * width + x0 + w) * 4), y * w * 4);
  return { data, width: w, height: h };
}
