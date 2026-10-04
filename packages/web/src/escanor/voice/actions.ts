import { matchApp, type InstalledApp } from './apps';
import type { ControlOp, PhoneAction, SettingsScreen } from './commands';

export interface PluginResult {
  ok: boolean;
  message?: string;
  /** The call was placed (not just the dialer opened). */
  direct?: boolean;
  /** What the person has to turn on for this to work. */
  needs?: 'accessibility' | 'controlBuild';
}

/** What the person has chosen about how the phone behaves for them. */
export interface PhoneOptions {
  /** Place calls themselves when Android's call permission is there. Off: only open the dialer. */
  directCalls?: boolean;
}

export interface ControlStatus {
  /** The person has switched Escanor on in Accessibility settings. */
  enabled: boolean;
  /** Phone control is part of this download. */
  available?: boolean;
  /** Android still greys out the switch ("Controlled by restricted setting"); null when this Android does not say. */
  restricted?: boolean | null;
}

/** What the native EscanorDevice plugin offers. (Declared here so the logic below can be tested with a fake phone.) */
export interface DevicePlugin {
  listApps(): Promise<{ apps: InstalledApp[] }>;
  launchPackage(o: { package: string }): Promise<PluginResult>;
  openUrl(o: { url: string }): Promise<PluginResult>;
  dial(o: { number: string }): Promise<PluginResult>;
  callNumber(o: { number: string; direct: boolean }): Promise<PluginResult>;
  callContact(o: { name: string; direct?: boolean }): Promise<PluginResult>;
  callStatus(): Promise<{ granted: boolean }>;
  requestCallPermission(): Promise<PluginResult>;
  controlStatus(): Promise<ControlStatus>;
  openControlSettings(): Promise<PluginResult>;
  /** Escanor's App info, where Android 13+ offers "Allow restricted settings". */
  openAppInfo(): Promise<PluginResult>;
  control(o: { action: 'global'; name: string } | { action: 'click'; text: string } | { action: 'scroll'; direction: 'up' | 'down' } | { action: 'type'; text: string } | { action: 'read' }): Promise<PluginResult>;
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
  /** What to turn on to make this work: the screen offers a button for it. */
  needs?: 'accessibility' | 'controlBuild';
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

const outcome = (r: PluginResult, good: string): ActionOutcome => (r.ok ? { ok: true, say: good } : { ok: false, say: r.message || TROUBLE, ...(r.needs ? { needs: r.needs } : {}) });

/** The phone's own buttons and gestures: what each is called when done, for the spoken answer. */
const CONTROL_DONE: Record<ControlOp, string> = { home: 'Going home.', back: 'Going back.', recents: 'Here are your recent apps.', notifications: 'Here are your notifications.', quick_settings: 'Here are your quick settings.', lock: 'Locking the phone.', screenshot: 'Taking a screenshot.', scroll_up: 'Scrolling up.', scroll_down: 'Scrolling down.' };

/** Said when the person has not turned the permission on: what to do, in this app and in Android. */
export const NEEDS_ACCESSIBILITY = 'To control your phone, Escanor needs the Accessibility permission. Open Settings, then Voice and phone control in this app, and turn it on.';

/**
 * Do one thing on the phone and say what happened. Never throws: whatever goes wrong becomes a sentence the assistant can speak.
 * With no phone plugin (the app in a browser) only opening a link works, and it says what is missing.
 */
export async function runPhoneAction(action: PhoneAction, dev: DevicePlugin | null, options: PhoneOptions = {}): Promise<ActionOutcome> {
  if (!dev) {
    if (action.type === 'open_app' && SITES[action.name]) {
      window.open(SITES[action.name], '_blank', 'noopener');
      return { ok: true, say: `Opening ${SITES[action.name].replace(/^https:\/\/(www\.)?/, '')}.` };
    }
    if (action.type === 'open_url') {
      window.open(action.url, '_blank', 'noopener');
      return { ok: true, say: `Opening ${action.url.replace(/^https:\/\/(www\.)?/, '')}.` };
    }
    return { ok: false, say: 'That works in the Android app. Open Escanor on your phone and ask again.' };
  }
  try {
    switch (action.type) {
      case 'open_app': {
        const site = SITES[action.name];
        const app = matchApp(action.name, (await dev.listApps()).apps);
        if (app) {
          const launched = await dev.launchPackage({ package: app.package });
          if (launched.ok) return { ok: true, say: `Opening ${app.label}.` };
          // The app is there but would not start: a site that does the same job is better than "that did not work".
          if (site) return outcome(await dev.openUrl({ url: site }), `Opening ${site.replace(/^https:\/\/(www\.)?/, '')} in the browser.`);
          return { ok: false, say: launched.message || `I could not open ${app.label}.` };
        }
        if (site) return outcome(await dev.openUrl({ url: site }), `Opening ${site.replace(/^https:\/\/(www\.)?/, '')}.`);
        return { ok: false, say: `I couldn’t find an app called ${action.name} on this phone.` };
      }
      case 'open_package':
        return outcome(await dev.launchPackage({ package: action.package }), `Opening ${action.label}.`);
      case 'open_url':
        return outcome(await dev.openUrl({ url: action.url }), `Opening ${action.url.replace(/^https:\/\/(www\.)?/, '').replace(/\/.*$/, '')}.`);
      case 'call': {
        const direct = options.directCalls !== false; // on unless the person turned it off; the phone still needs Android's call permission
        const placed = (r: PluginResult, who: string): ActionOutcome => (!r.ok ? { ok: false, say: r.message || TROUBLE } : r.direct ? { ok: true, say: `Calling ${who}.` } : { ok: true, say: `Opening the dialer with ${who}. Press call to ring.${r.message && r.message !== who ? ` ${r.message}` : ''}` });
        if (/^\+?\d{3,}$/.test(action.who)) return placed(await dev.callNumber({ number: action.who, direct }), action.who);
        const r = await dev.callContact({ name: action.who, direct });
        return placed(r, r.ok && r.message ? r.message : action.who);
      }
      case 'control': {
        if (action.op === 'scroll_up' || action.op === 'scroll_down') return outcome(await dev.control({ action: 'scroll', direction: action.op === 'scroll_up' ? 'up' : 'down' }), CONTROL_DONE[action.op]);
        return outcome(await dev.control({ action: 'global', name: action.op }), CONTROL_DONE[action.op]);
      }
      case 'tap_text':
        return outcome(await dev.control({ action: 'click', text: action.text }), `Tapped ${action.text}.`);
      case 'type_text':
        return outcome(await dev.control({ action: 'type', text: action.text }), 'Typed it.');
      case 'read_screen': {
        const r = await dev.control({ action: 'read' });
        return r.ok ? { ok: true, say: `On your screen: ${r.message}` } : outcome(r, '');
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
