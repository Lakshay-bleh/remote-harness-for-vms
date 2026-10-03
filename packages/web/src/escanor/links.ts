import { Browser } from '@capacitor/browser';
import { isNative } from '../api';

/**
 * Open a web page outside the app (the system browser on the phone). Only https: this is never given anything else.
 * Used for the one thing that must happen in a browser: signing in to Google and to the services you connect (their consent
 * pages cannot be shown inside another app). Everything else (plan and billing, team, security, data, help, legal) is in the app.
 */
export function openExternal(url: string): void {
  if (!/^https:\/\//i.test(url)) return;
  if (isNative()) void Browser.open({ url });
  else window.open(url, '_blank', 'noopener,noreferrer');
}
