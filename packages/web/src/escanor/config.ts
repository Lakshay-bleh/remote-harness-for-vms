import { isNative } from '../api';

const LEGACY_OVERRIDE_KEY = 'escanor_api_url';
const DEFAULT_API = 'https://api.escanor.in/api/v1';

// The app used to let a custom server be typed in Developer settings. That sent the person's sign-in to whatever address was entered,
// and nothing needed it, so it is gone: forget any address saved by an older version.
try {
  if (typeof localStorage !== 'undefined') localStorage.removeItem(LEGACY_OVERRIDE_KEY);
} catch {
  // storage unavailable: nothing to forget
}

/** Where the Escanor backend is: always Escanor's own server. Only a build made for development (VITE_ESCANOR_API) points elsewhere. */
export function escanorApiBase(): string {
  const built = (import.meta as { env?: Record<string, string> }).env?.VITE_ESCANOR_API;
  return (built || DEFAULT_API).replace(/\/+$/, '');
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
