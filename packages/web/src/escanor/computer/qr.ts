import jsQR from 'jsqr';

/**
 * Read a QR code out of one camera frame (RGBA pixels). This is plain JavaScript on purpose: Android's WebView has no
 * `BarcodeDetector`, which is what the scanner used before, so on the phone it never found anything.
 */
export function decodeQr(rgba: Uint8ClampedArray, width: number, height: number): string | null {
  return jsQR(rgba, width, height, { inversionAttempts: 'dontInvert' })?.data ?? null;
}
