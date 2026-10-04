import { escanor, hasStoredSession } from '../client';
import type { DevicePlugin } from './actions';
import { appsForServer, type ServerPlan } from './serverPlan';

let cached: { at: number; apps: Array<{ id: string; label: string }> } | null = null;
const FRESH_MS = 60_000;

/** This phone's apps for the server, listed at most once a minute (listing is the slow part). */
async function phoneApps(dev: DevicePlugin | null): Promise<Array<{ id: string; label: string }>> {
  if (!dev) return [];
  if (cached && Date.now() - cached.at < FRESH_MS) return cached.apps;
  try {
    const apps = appsForServer((await dev.listApps()).apps);
    cached = { at: Date.now(), apps };
    return apps;
  } catch {
    return [];
  }
}

/** Ask the server's voice brain about a sentence. Null when signed out, offline, or anything goes wrong: the caller carries on without it. */
export async function resolveOnServer(text: string, dev: DevicePlugin | null): Promise<ServerPlan | null> {
  if (!hasStoredSession()) return null;
  try {
    return await escanor.voiceResolve({ text, client: 'mobile', device: { platform: 'android', apps: await phoneApps(dev) } });
  } catch {
    return null;
  }
}
