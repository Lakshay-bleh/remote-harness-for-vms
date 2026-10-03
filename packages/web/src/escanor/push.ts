import { PushNotifications } from '@capacitor/push-notifications';
import { isNative } from '../api';
import { escanor } from './client';

/** unsupported: not the Android app. unavailable: it is, but this build was made without Firebase's config, so it cannot register. */
export type PushState = 'unsupported' | 'unavailable' | 'off' | 'on' | 'denied';
export type PushDest = 'assistant' | 'computers' | 'connections' | 'machines' | 'settings';

/** The Android notification channel the backend names in every message. Keep the two in step. */
export const CHANNEL_ID = 'escanor_alerts';
const TOKEN_KEY = 'escanor.push.token';

const ROUTES: Record<string, PushDest> = {
  deployment_approvals: 'assistant',
  emergency_alerts: 'assistant',
  team_pings: 'assistant',
  server_down: 'machines',
};

/** Where tapping a notification should land. Anything unexpected opens the main screen. */
export function routeFor(data: unknown): PushDest {
  const kind = data && typeof data === 'object' ? (data as { kind?: unknown }).kind : undefined;
  return typeof kind === 'string' && Object.hasOwn(ROUTES, kind) ? ROUTES[kind] : 'assistant';
}

export type ChannelState = 'ok' | 'quiet' | 'blocked' | 'missing';

/** Can the Alerts channel actually show a notification? (Android: 0 = switched off, 1-2 = silent only, 3+ = normal.) */
export function channelState(channels: Array<{ id: string; importance?: number }> | undefined): ChannelState {
  const c = channels?.find((x) => x.id === CHANNEL_ID);
  const importance = c?.importance ?? 3; // not reported: assume normal
  return !c ? 'missing' : importance <= 0 ? 'blocked' : importance < 3 ? 'quiet' : 'ok';
}

/** Ask Android how the Alerts channel is set right now (the person can change it in the phone's settings at any time). */
export async function alertChannelState(): Promise<ChannelState | null> {
  if (!isNative()) return null;
  try {
    return channelState((await PushNotifications.listChannels()).channels);
  } catch {
    return null;
  }
}

export function stateFromPermission(p: string): 'off' | 'on' | 'denied' {
  return p === 'granted' ? 'on' : p === 'denied' ? 'denied' : 'off';
}

const stored = (): string | null => {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
};
const remember = (t: string | null) => {
  try {
    t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY);
  } catch {
    // best effort: without it, forgetting this phone on sign-out can only be done by the server dropping dead tokens
  }
};

let wired = false;
/** Send this phone's address to Escanor whenever Android hands out (or refreshes) it. */
function wireRegistration(): void {
  if (wired) return;
  wired = true;
  void PushNotifications.addListener('registration', ({ value }) => {
    remember(value);
    void escanor.registerPushToken(value).catch(() => undefined); // retried at the next start
  });
  void PushNotifications.addListener('registrationError', () => undefined);
}

async function createChannel(): Promise<void> {
  // Android 8+ shows nothing without a channel; this one is high-importance so approvals make a sound.
  await PushNotifications.createChannel({ id: CHANNEL_ID, name: 'Alerts', description: 'Approvals, outages and messages from your team', importance: 4, visibility: 1 }).catch(() => undefined);
}

export async function pushState(): Promise<PushState> {
  if (!isNative()) return 'unsupported';
  try {
    return stateFromPermission((await PushNotifications.checkPermissions()).receive);
  } catch {
    return 'unsupported';
  }
}

/** Ask the person's permission (Android 13+), then register this phone. Returns where that left things. */
export async function enablePush(): Promise<PushState> {
  if (!isNative()) return 'unsupported';
  try {
    let p = (await PushNotifications.checkPermissions()).receive;
    if (p !== 'granted') p = (await PushNotifications.requestPermissions()).receive;
    if (p !== 'granted') return stateFromPermission(p);
    wireRegistration();
    await createChannel();
    await PushNotifications.register();
    return 'on';
  } catch {
    return 'unavailable'; // typically: no google-services.json in this build
  }
}

/** At app start: if they already said yes, register again (Android may have changed the address). Never asks. */
export async function resumePush(): Promise<void> {
  if ((await pushState()) === 'on') await enablePush();
}

/** On sign-out: tell Escanor to stop sending this phone anything, so the next person to use it does not get these alerts. */
export async function forgetPush(): Promise<void> {
  const token = stored();
  remember(null);
  if (isNative()) await PushNotifications.unregister().catch(() => undefined);
  if (token) await escanor.unregisterPushToken(token).catch(() => undefined);
}

/** Tapping a notification, and one arriving while the app is open. Returns how to stop listening. */
export function listenPush(onOpen: (dest: PushDest) => void, onForeground: (n: { title: string; body: string; dest: PushDest }) => void): () => void {
  if (!isNative()) return () => undefined;
  const subs = [
    PushNotifications.addListener('pushNotificationActionPerformed', (a) => onOpen(routeFor(a.notification.data))),
    PushNotifications.addListener('pushNotificationReceived', (n) => onForeground({ title: n.title ?? 'Escanor', body: n.body ?? '', dest: routeFor(n.data) })),
  ];
  return () => subs.forEach((s) => void s.then((h) => h.remove()));
}
