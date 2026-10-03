import { Browser } from '@capacitor/browser';
import { isNative } from '../api';
import { escanor, hasStoredSession } from './client';

/** Open a web page outside the app (the system browser on the phone). Only https: this is never given anything else. */
export function openExternal(url: string): void {
  if (!/^https:\/\//i.test(url)) return;
  if (isNative()) void Browser.open({ url });
  else window.open(url, '_blank', 'noopener,noreferrer');
}

export const SITE = 'https://www.escanor.in';
export const LINKS = {
  privacy: `${SITE}/privacy`,
  terms: `${SITE}/terms`,
  support: `${SITE}/support`,
  accountSettings: `${SITE}/dashboard/settings`,
  billing: `${SITE}/dashboard/settings/billing`,
} as const;

/**
 * Open a page of the website. The browser it opens is not signed in, so a signed-in app first asks Escanor for a one-minute link that
 * signs it in and lands on `path`. If that is not possible (offline, an old server) the plain page opens and the website asks to sign in.
 */
export async function openWeb(path: string): Promise<void> {
  if (!path.startsWith('/')) return;
  if (hasStoredSession()) {
    try {
      return openExternal(await escanor.webHandoff(path));
    } catch {
      // fall through to the plain page
    }
  }
  openExternal(`${SITE}${path}`);
}
