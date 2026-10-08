import { isIOS } from '../../api';
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

export interface ResolveBody {
  text: string;
  client: 'mobile';
  device: { platform: 'android' | 'ios'; apps: Array<{ id: string; label: string }> };
}

export interface ResolveOptions {
  /** The voice turn's signal: cancelling voice mode cancels the request. */
  signal?: AbortSignal;
  /** Which phone this is (defaults to asking Capacitor). */
  ios?: boolean;
  /** For tests: what sends the request, and whether someone is signed in. */
  send?: (body: ResolveBody, signal?: AbortSignal) => Promise<ServerPlan>;
  signedIn?: () => boolean;
}

/** Ask the server's voice brain about a sentence. Null when signed out, offline, cancelled, or anything goes wrong: the caller carries on without it. */
export async function resolveOnServer(text: string, dev: DevicePlugin | null, o: ResolveOptions = {}): Promise<ServerPlan | null> {
  if (!(o.signedIn ?? hasStoredSession)()) return null;
  const send = o.send ?? ((body: ResolveBody, signal?: AbortSignal) => escanor.voiceResolve(body, signal));
  try {
    if (o.signal?.aborted) return null;
    const platform = (o.ios ?? isIOS()) ? 'ios' : 'android';
    return await send({ text, client: 'mobile', device: { platform, apps: await phoneApps(dev) } }, o.signal);
  } catch {
    return null;
  }
}
