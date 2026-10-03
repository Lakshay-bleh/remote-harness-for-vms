import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import QRCode from 'qrcode';
import { centreCrop, decodeQr, decodeQrHard } from './qr';
import { parseEntry } from './pairing';
import { formatCode, randomBytes } from './lib/secure';

/** Rasterise a QR the way a camera frame looks: dark modules on white, with a quiet zone, scaled up. */
function frame(text: string, scale = 6, margin = 4, dark = 20, light = 255) {
  const qr = QRCode.create(text, { errorCorrectionLevel: 'M' });
  const n = qr.modules.size;
  const size = (n + margin * 2) * scale;
  const rgba = new Uint8ClampedArray(size * size * 4).fill(light);
  for (let i = 3; i < rgba.length; i += 4) rgba[i] = 255;
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++)
      if (qr.modules.get(y, x))
        for (let dy = 0; dy < scale; dy++)
          for (let dx = 0; dx < scale; dx++) {
            const i = (((y + margin) * scale + dy) * size + (x + margin) * scale + dx) * 4;
            rgba[i] = rgba[i + 1] = rgba[i + 2] = dark;
          }
  return { rgba, width: size, height: size };
}

describe('decodeQr', () => {
  it('reads the QR that Escanor Desktop shows, and the result is a valid pairing', () => {
    const code = formatCode(randomBytes(20));
    const payload = JSON.stringify({ v: 1, code, machine: 'Work Laptop', lan: ['192.168.1.20:47625', '100.101.102.103:47625'], agentId: 'agent-1' });
    const f = frame(payload);
    const text = decodeQr(f.rgba, f.width, f.height);
    assert.equal(text, payload);
    assert.equal(parseEntry(text!)?.payload?.agentId, 'agent-1');
  });

  it('reads it at the small sizes a phone camera produces', () => {
    const payload = JSON.stringify({ v: 1, code: formatCode(randomBytes(20)), machine: 'x', lan: [], agentId: null });
    const f = frame(payload, 3);
    assert.equal(decodeQr(f.rgba, f.width, f.height), payload);
  });

  it('returns null for a frame with no code in it', () => {
    const blank = new Uint8ClampedArray(200 * 200 * 4).fill(128);
    assert.equal(decodeQr(blank, 200, 200), null);
  });
});

const PAYLOAD = () => JSON.stringify({ v: 1, code: formatCode(randomBytes(20)), machine: 'Work Laptop', lan: ['192.168.1.20:47625', '100.101.102.103:47625'], agentId: '6f2c1f0e-1d3a-4d79-9a0e-5b2a6f0c1d11' });

describe('poor conditions', () => {
  it('reads a light-on-dark code (a screen in dark mode)', () => {
    const p = PAYLOAD();
    const f = frame(p, 5, 4, 250, 15);
    assert.equal(decodeQr(f.rgba, f.width, f.height), p);
  });

  it('reads a dim, low-contrast code (a screen turned down, seen in a dark room)', () => {
    const p = PAYLOAD();
    const f = frame(p, 5, 4, 55, 80);
    assert.equal(decodeQrHard(f.rgba, f.width, f.height), p);
  });

  it('reads a code with a shadow across it (lit from one side)', () => {
    const p = PAYLOAD();
    const f = frame(p, 5, 4, 20, 255);
    for (let y = 0; y < f.height; y++)
      for (let x = 0; x < f.width; x++) {
        const k = 0.28 + 0.72 * (x / f.width); // a left-to-right ramp from deep shade to full light
        const i = (y * f.width + x) * 4;
        f.rgba[i] = f.rgba[i + 1] = f.rgba[i + 2] = Math.round(f.rgba[i] * k);
      }
    assert.equal(decodeQrHard(f.rgba, f.width, f.height), p);
  });

  it('reads a code that is small in the frame, once cropped to the aiming box and the rest is clutter', () => {
    const p = PAYLOAD();
    const code = frame(p, 4);
    const W = code.width * 2, H = code.height * 2;
    const rgba = new Uint8ClampedArray(W * H * 4);
    for (let i = 0; i < W * H; i++) { rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = 90 + ((i * 2654435761) >>> 24) % 110; rgba[i * 4 + 3] = 255; } // clutter
    const ox = (W - code.width) / 2, oy = (H - code.height) / 2;
    for (let y = 0; y < code.height; y++) rgba.set(code.rgba.subarray(y * code.width * 4, (y + 1) * code.width * 4), ((oy + y) * W + ox) * 4);
    const c = centreCrop(rgba, W, H, 0.6);
    assert.equal(decodeQrHard(c.data, c.width, c.height), p);
  });

  it('still returns null for a frame with nothing in it', () => {
    const blank = new Uint8ClampedArray(240 * 240 * 4).fill(128);
    assert.equal(decodeQrHard(blank, 240, 240), null);
  });
});
