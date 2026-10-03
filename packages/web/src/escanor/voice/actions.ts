import { matchApp, type InstalledApp } from './apps';
import type { PhoneAction, SettingsScreen } from './commands';

export interface PluginResult {
  ok: boolean;
  message?: string;
}

/** What the native EscanorDevice plugin offers. (Declared here so the logic below can be tested with a fake phone.) */
export interface DevicePlugin {
  listApps(): Promise<{ apps: InstalledApp[] }>;
  launchPackage(o: { package: string }): Promise<PluginResult>;
  openUrl(o: { url: string }): Promise<PluginResult>;
  dial(o: { number: string }): Promise<PluginResult>;
  callContact(o: { name: string }): Promise<PluginResult>;
  setAlarm(o: { hour: number; minute: number }): Promise<PluginResult>;
  setTimer(o: { seconds: number }): Promise<PluginResult>;
  setTorch(o: { on: boolean }): Promise<PluginResult>;
  setVolume(o: { change: 'up' | 'down' | 'mute' | 'unmute' }): Promise<PluginResult>;
  openSettings(o: { screen: SettingsScreen | 'main' }): Promise<PluginResult>;
}

export interface ActionOutcome {
  ok: boolean;
  /** What to say (and show) to the person. */
  say: string;
}

/** Sites that have no app on the phone but are worth opening when asked by name. */
const SITES: Record<string, string> = {
  youtube: 'https://www.youtube.com',
  google: 'https://www.google.com',
  github: 'https://github.com',
  gmail: 'https://mail.google.com',
  maps: 'https://maps.google.com',
  'google maps': 'https://maps.google.com',
  netflix: 'https://www.netflix.com',
  amazon: 'https://www.amazon.com',
  spotify: 'https://open.spotify.com',
  whatsapp: 'https://web.whatsapp.com',
  twitter: 'https://x.com',
  linkedin: 'https://www.linkedin.com',
  reddit: 'https://www.reddit.com',
  wikipedia: 'https://www.wikipedia.org',
  chatgpt: 'https://chatgpt.com',
  escanor: 'https://www.escanor.in',
};

export function formatClock(hour: number, minute: number): string {
  const h = hour % 12 === 0 ? 12 : hour % 12;
  return `${h}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`;
}

export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  const part = (n: number, unit: string) => `${n} ${unit}${n === 1 ? '' : 's'}`;
  return [h && part(h, 'hour'), m && part(m, 'minute'), s && part(s, 'second')].filter(Boolean).join(' ');
}

const SCREEN_NAMES: Record<string, string> = { wifi: 'Wi-Fi', bluetooth: 'Bluetooth', display: 'display', sound: 'sound', battery: 'battery', apps: 'apps', location: 'location' };
const VOLUME_WORDS = { up: 'Volume up.', down: 'Volume down.', mute: 'Muted.', unmute: 'Unmuted.' } as const;
const TROUBLE = 'I could not do that on this phone.';

const outcome = (r: PluginResult, good: string): ActionOutcome => (r.ok ? { ok: true, say: good } : { ok: false, say: r.message || TROUBLE });

/**
 * Do one thing on the phone and say what happened. Never throws: whatever goes wrong becomes a sentence the assistant can speak.
 * With no phone plugin (the app in a browser) only opening a link works, and it says what is missing.
 */
export async function runPhoneAction(action: PhoneAction, dev: DevicePlugin | null): Promise<ActionOutcome> {
  if (!dev) {
    if (action.type === 'open_app' && SITES[action.name]) {
      window.open(SITES[action.name], '_blank', 'noopener');
      return { ok: true, say: `Opening ${SITES[action.name].replace(/^https:\/\/(www\.)?/, '')}.` };
    }
    return { ok: false, say: 'That works in the Android app. Open Escanor on your phone and ask again.' };
  }
  try {
    switch (action.type) {
      case 'open_app': {
        const app = matchApp(action.name, (await dev.listApps()).apps);
        if (app) return outcome(await dev.launchPackage({ package: app.package }), `Opening ${app.label}.`);
        const site = SITES[action.name];
        if (site) return outcome(await dev.openUrl({ url: site }), `Opening ${site.replace(/^https:\/\/(www\.)?/, '')}.`);
        return { ok: false, say: `I couldn’t find an app called ${action.name} on this phone.` };
      }
      case 'open_package':
        return outcome(await dev.launchPackage({ package: action.package }), `Opening ${action.label}.`);
      case 'open_url':
        return outcome(await dev.openUrl({ url: action.url }), `Opening ${action.url.replace(/^https:\/\/(www\.)?/, '').replace(/\/.*$/, '')}.`);
      case 'call': {
        if (/^\+?\d{3,}$/.test(action.who)) return outcome(await dev.dial({ number: action.who }), `Opening the dialer with ${action.who}. Press call to ring.`);
        const r = await dev.callContact({ name: action.who });
        return r.ok ? { ok: true, say: `Opening the dialer for ${r.message || action.who}. Press call to ring.` } : { ok: false, say: r.message || TROUBLE };
      }
      case 'alarm':
        return outcome(await dev.setAlarm({ hour: action.hour, minute: action.minute }), `Alarm set for ${formatClock(action.hour, action.minute)}.`);
      case 'timer':
        return outcome(await dev.setTimer({ seconds: action.seconds }), `Timer set for ${formatDuration(action.seconds)}.`);
      case 'torch':
        return outcome(await dev.setTorch({ on: action.on }), action.on ? 'Flashlight on.' : 'Flashlight off.');
      case 'volume':
        return outcome(await dev.setVolume({ change: action.change }), VOLUME_WORDS[action.change]);
      case 'web_search':
        return outcome(await dev.openUrl({ url: `https://www.google.com/search?q=${encodeURIComponent(action.query)}` }), `Searching for ${action.query}.`);
      case 'settings':
        return outcome(await dev.openSettings({ screen: action.screen }), `Opening ${SCREEN_NAMES[action.screen] ?? action.screen} settings.`);
    }
  } catch {
    return { ok: false, say: TROUBLE };
  }
}
