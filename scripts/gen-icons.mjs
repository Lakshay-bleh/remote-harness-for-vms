// Builds every app icon from the full-resolution Escanor logo
// (packages/web/assets/escanor-logo.png), so the launcher icon, splash, PWA
// icons and favicon all show the same mark, sharp, centred and inside the
// adaptive-icon safe zone. Run `npm run gen:icons`, then
// `npx capacitor-assets generate --android` (from packages/web) to fan the
// 1024px sources out into the Android mipmaps and splash screens.
import sharp from 'sharp';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = resolve(dirname(fileURLToPath(import.meta.url)), '../packages/web');
const LOGO = resolve(web, 'assets/escanor-logo.png');
const SIZE = 1024;
// The visual centre of the artwork (sphere + swoosh), in logo pixels. Centring on
// this, not the image centre, keeps the mark balanced in the square.
const CENTER = { x: 380, y: 355 };
const INK = { r: 5, g: 5, b: 5 };

const logoMeta = await sharp(LOGO).metadata();

/** The logo on a transparent SIZE x SIZE canvas, artwork centre at canvas centre. */
async function foreground() {
  const left = Math.round(SIZE / 2 - CENTER.x);
  const top = Math.round(SIZE / 2 - CENTER.y);
  return sharp({ create: { width: SIZE, height: SIZE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: LOGO, left, top }])
    .png()
    .toBuffer();
}

/** Dark ground with a faint warm glow behind the mark, so gold reads as light. */
function background() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">
    <defs><radialGradient id="g" cx="50%" cy="50%" r="60%">
      <stop offset="0" stop-color="#1c1409"/><stop offset="1" stop-color="#050505"/>
    </radialGradient></defs>
    <rect width="100%" height="100%" fill="url(#g)"/></svg>`;
  return sharp(Buffer.from(svg)).png().toBuffer();
}

const fg = await foreground();
const bg = await background();
const full = await sharp(bg).composite([{ input: fg }]).png().toBuffer();

const out = (p) => resolve(web, p);
await sharp(fg).toFile(out('assets/icon-foreground.png'));
await sharp(bg).toFile(out('assets/icon-background.png'));
await sharp(full).toFile(out('assets/icon-only.png'));
// Splash: the mark on the ink ground, small enough to leave air around it.
await sharp({ create: { width: 2732, height: 2732, channels: 3, background: INK } })
  .composite([{ input: await sharp(full).resize(900).toBuffer(), gravity: 'center' }])
  .png()
  .toFile(out('assets/splash.png'));
await sharp(full).resize(192).png({ compressionLevel: 9 }).toFile(out('public/icon-192.png'));
await sharp(full).resize(512).png({ compressionLevel: 9 }).toFile(out('public/icon-512.png'));
console.log(`icons written from ${LOGO} (${logoMeta.width}x${logoMeta.height})`);
