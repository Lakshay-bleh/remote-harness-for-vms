import { Browser } from '@capacitor/browser';
import { isNative } from '../api';

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
