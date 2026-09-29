import { isNative } from '../api';

const API_KEY = 'escanor_api_url';
const DEFAULT_API = 'https://api.escanor.in/api/v1';

/** Where the Escanor backend is. Overridable for development (`localStorage.escanor_api_url`) or at build time. */
export function escanorApiBase(): string {
  const stored = typeof localStorage !== 'undefined' ? localStorage.getItem(API_KEY) : null;
  const built = (import.meta as { env?: Record<string, string> }).env?.VITE_ESCANOR_API;
  return (stored || built || DEFAULT_API).replace(/\/+$/, '');
}

export function setEscanorApiBase(url: string | null): void {
  if (url && /^https?:\/\//.test(url)) localStorage.setItem(API_KEY, url.trim());
  else localStorage.removeItem(API_KEY);
}

/** Custom scheme the Android app owns; the Escanor site's /auth/mobile page hands the login code to it. */
export const APP_SCHEME = 'escanor';
export const MOBILE_LOGIN_REDIRECT = 'https://www.escanor.in/auth/mobile/login';

/**
 * Where the backend should send the person after Google. In the native app that is a page on
 * escanor.in that hands the code to the app; in a browser it is this very app -- but the backend only
 * returns to localhost or *.escanor.in, so anywhere else cannot complete a sign-in here.
 */
export function loginRedirect(): { uri: string; supported: boolean } {
  if (isNative()) return { uri: MOBILE_LOGIN_REDIRECT, supported: true };
  const host = window.location.hostname;
  const supported = host === 'localhost' || host === '127.0.0.1' || host === 'escanor.in' || host.endsWith('.escanor.in');
  return { uri: `${window.location.origin}/auth/callback`, supported };
}
