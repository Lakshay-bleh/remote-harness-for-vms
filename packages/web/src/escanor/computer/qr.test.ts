import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import QRCode from 'qrcode';
import { decodeQr } from './qr';
import { parseEntry } from './pairing';
import { formatCode, randomBytes } from './lib/secure';

/** Rasterise a QR the way a camera frame looks: dark modules on white, with a quiet zone, scaled up. */
function frame(text: string, scale = 6, margin = 4) {
  const qr = QRCode.create(text, { errorCorrectionLevel: 'M' });
  const n = qr.modules.size;
  const size = (n + margin * 2) * scale;
  const rgba = new Uint8ClampedArray(size * size * 4).fill(255);
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++)
      if (qr.modules.get(y, x))
        for (let dy = 0; dy < scale; dy++)
          for (let dx = 0; dx < scale; dx++) {
            const i = (((y + margin) * scale + dy) * size + (x + margin) * scale + dx) * 4;
            rgba[i] = rgba[i + 1] = rgba[i + 2] = 20;
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
