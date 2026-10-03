import { BarcodeFormat, BarcodeScanner } from '@capacitor-mlkit/barcode-scanning';
import { isNative } from '../../api';

export type ScanFailure = 'cancelled' | 'unavailable' | 'failed';

/** What went wrong in the native scanner, in the three ways the caller cares about. */
export function classifyScanError(e: unknown): ScanFailure {
  const m = (e instanceof Error ? e.message : typeof e === 'string' ? e : '').toLowerCase();
  if (/cancel/.test(m)) return 'cancelled';
  if (/not available|not implemented|not installed|modulenot|play services|unavailable/.test(m)) return 'unavailable';
  return 'failed';
}

/** The first QR value the scanner read, if any. */
export function firstQr(r: { barcodes?: Array<{ rawValue?: string }> } | null | undefined): string | null {
  return r?.barcodes?.find((b) => typeof b.rawValue === 'string' && b.rawValue.length > 0)?.rawValue ?? null;
}

/**
 * Scan a QR code with the phone's own scanner (Google's code scanner: the native camera with real autofocus, exposure and
 * low-light handling, and no camera permission). The web view's camera is the weak link on Android, which is why this exists.
 * Resolves with the text, or null if the person closed it. Rejects with a ScanFailure message when it cannot run here.
 */
export async function scanWithNative(): Promise<string | null> {
  if (!isNative()) throw new Error('unavailable: not the Android app');
  try {
    const { available } = await BarcodeScanner.isGoogleBarcodeScannerModuleAvailable();
    if (!available) await BarcodeScanner.installGoogleBarcodeScannerModule(); // Google Play delivers it once; first use only
    return firstQr(await BarcodeScanner.scan({ formats: [BarcodeFormat.QrCode] }));
  } catch (e) {
    if (classifyScanError(e) === 'cancelled') return null;
    throw e instanceof Error ? e : new Error(String(e));
  }
}
