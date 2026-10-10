import type { InstalledApp } from './apps';
import type { PhoneAction, SettingsScreen } from './commands';

/** What the server's voice brain (POST /ai/voice/resolve) answers: what to say, and the actions to run on this phone. */
export interface ServerPlan {
  source: 'rules' | 'llm' | 'none' | 'error';
  say: string;
  actions: ServerAction[];
  /** The `say` is a question: speak it and listen again. */
  needs: 'clarify' | null;
  /** Not something to do on the device: the app's own assistant should have it. */
  not_device?: boolean;
  /** `say` is the answer to small talk or a general question: just speak it. */
  chat?: boolean;
  /** `say` is a short acknowledgement ("Checking your services."): speak it now and hand the sentence to the full assistant. */
  delegate?: boolean;
  /** No AI model answered in time; `say` is a stand-in so the person is never left with an error for a simple question. */
  degraded?: string;
  model?: string;
}

export type ServerAction =
  | { type: 'open_app'; id: string; label: string; unresolved?: boolean }
  | { type: 'open_url'; url: string }
  | { type: 'web_search'; query: string; site?: string; url?: string }
  | { type: 'call'; who: string }
  | { type: 'alarm'; hour: number; minute: number }
  | { type: 'timer'; seconds: number }
  | { type: 'torch'; on: boolean }
  | { type: 'volume'; change: 'up' | 'down' | 'mute' | 'unmute' }
  | { type: 'media'; action: 'playpause' | 'next' | 'previous' }
  | { type: 'settings'; screen: SettingsScreen }
  | { type: 'stop' };

const isHttps = (u: unknown): u is string => typeof u === 'string' && /^https:\/\/[^\s]+$/i.test(u);

/**
 * Turn the server's actions into things this phone can do. Anything the phone cannot do, or that does not look right, is dropped
 * and counted (the server is trusted to decide, not to be obeyed blindly: an unknown shape never reaches the phone's plugin).
 */
export function planToActions(plan: Pick<ServerPlan, 'actions'>): { actions: PhoneAction[]; skipped: number; stop: boolean } {
  const out: PhoneAction[] = [];
  let skipped = 0;
  let stop = false;
  for (const a of Array.isArray(plan.actions) ? plan.actions : []) {
    switch (a?.type) {
      case 'open_app':
        // Chosen from this phone's own list on the server: open it by package. If the phone could not list its apps the server hands
        // the spoken name back, and the phone looks it up itself.
        if (a.unresolved && typeof a.label === 'string') out.push({ type: 'open_app', name: a.label });
        else if (typeof a.id === 'string' && a.id && typeof a.label === 'string') out.push({ type: 'open_package', package: a.id, label: a.label });
        else skipped += 1;
        break;
      case 'open_url':
        isHttps(a.url) ? out.push({ type: 'open_url', url: a.url }) : (skipped += 1);
        break;
      case 'web_search':
        isHttps(a.url) ? out.push({ type: 'open_url', url: a.url }) : typeof a.query === 'string' && a.query ? out.push({ type: 'web_search', query: a.query }) : (skipped += 1);
        break;
      case 'call':
        typeof a.who === 'string' && a.who ? out.push({ type: 'call', who: a.who }) : (skipped += 1);
        break;
      case 'alarm':
        Number.isInteger(a.hour) && Number.isInteger(a.minute) && a.hour >= 0 && a.hour <= 23 && a.minute >= 0 && a.minute <= 59 ? out.push({ type: 'alarm', hour: a.hour, minute: a.minute }) : (skipped += 1);
        break;
      case 'timer':
        Number.isInteger(a.seconds) && a.seconds > 0 && a.seconds <= 86_400 ? out.push({ type: 'timer', seconds: a.seconds }) : (skipped += 1);
        break;
      case 'torch':
        typeof a.on === 'boolean' ? out.push({ type: 'torch', on: a.on }) : (skipped += 1);
        break;
      case 'volume':
        ['up', 'down', 'mute', 'unmute'].includes(a.change) ? out.push({ type: 'volume', change: a.change }) : (skipped += 1);
        break;
      case 'settings':
        typeof a.screen === 'string' ? out.push({ type: 'settings', screen: a.screen }) : (skipped += 1);
        break;
      case 'media':
        ['playpause', 'next', 'previous'].includes(a.action) ? out.push({ type: 'media', action: a.action }) : (skipped += 1);
        break;
      case 'stop':
        stop = true; // "stop", "that's all": end the conversation, nothing to run
        break;
      default:
        skipped += 1; // anything new: this phone has no way to do it yet
    }
  }
  return { actions: out.slice(0, 3), skipped, stop };
}

/** The phone's apps, as the server wants them. */
export const appsForServer = (apps: InstalledApp[]): Array<{ id: string; label: string }> => apps.map((a) => ({ id: a.package, label: a.label }));
