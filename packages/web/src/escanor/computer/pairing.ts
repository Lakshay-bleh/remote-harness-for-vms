import { normalizeLanAddress, pairByAddress, pairWithCode, pairWithPayload, type ClientEnv, type CloudDirectory, type PairedComputer } from './lib/client';
import type { LanAskOptions } from './lib/lan-pair';
import type { PairingPayload } from './lib/protocol';
import { formatCode, parseCode } from './lib/secure';

/** What a person typed, pasted or scanned: the code, and (from a QR) which computer it belongs to and where it is on Wi-Fi. */
export interface PairEntry {
  code: string;
  payload?: PairingPayload;
}

/** Accepts a typed code (any case, dashes or spaces) or the QR's JSON. Anything else is not a pairing. */
export function parseEntry(text: string): PairEntry | null {
  const t = text.trim();
  if (!t) return null;
  if (t.startsWith('{')) {
    try {
      const v = JSON.parse(t) as Partial<PairingPayload>;
      if (v && v.v === 1 && typeof v.code === 'string' && Array.isArray(v.lan)) {
        const code = formatCode(parseCode(v.code));
        return { code, payload: { v: 1, code, machine: typeof v.machine === 'string' ? v.machine : 'My computer', lan: v.lan.filter((a): a is string => typeof a === 'string'), agentId: typeof v.agentId === 'string' ? v.agentId : null } };
      }
    } catch {
      return null;
    }
    return null;
  }
  try {
    return { code: formatCode(parseCode(t)) };
  } catch {
    return null;
  }
}

/** `host:port` or null: the address of a computer on the local network. The port is optional, and a pasted `http://…/` is fine. */
export const normalizeAddress = normalizeLanAddress;

/**
 * Pair with a computer on the same Wi-Fi knowing only its address, with no code: the person approves on the computer after checking
 * that it shows the same confirmation number as this phone (`onConfirm` receives it).
 */
export const pairOnWifi = (address: string, deviceName: string, o: LanAskOptions & { env?: ClientEnv } = {}): Promise<PairedComputer> => pairByAddress(address, deviceName, o);

export interface PairOptions {
  /** `cloud` (the default): the code alone, from anywhere. `lan`: straight to the computer over the same Wi-Fi. */
  mode: 'cloud' | 'lan';
  cloud: CloudDirectory;
  /** Local mode, when the code was typed rather than scanned. */
  lanAddress?: string;
  env?: ClientEnv;
}

/** The cloud could not be reached at all (as opposed to the computer saying no). Only then is the local network worth a try. */
const cloudUnreachable = (e: unknown) => e instanceof Error && /could not reach|did not answer|offline|timed out|failed to fetch|network/i.test(e.message);

export async function pairComputer(entry: PairEntry, deviceName: string, o: PairOptions): Promise<PairedComputer> {
  const p = entry.payload;
  const local = (addresses: string[]) => pairWithPayload({ v: 1, code: entry.code, machine: p?.machine ?? 'My computer', lan: addresses, agentId: p?.agentId ?? null }, deviceName, o.env);

  if (o.mode === 'lan') {
    const typed = o.lanAddress ? normalizeAddress(o.lanAddress) : null;
    const addresses = p?.lan.length ? p.lan : typed ? [typed] : [];
    if (addresses.length === 0) throw new Error('Enter the address shown on your computer, like 192.168.1.20.');
    return local(addresses);
  }
  try {
    return await pairWithCode(entry.code, deviceName, o.cloud, { agentId: p?.agentId, machine: p?.machine, lan: p?.lan });
  } catch (e) {
    if (p?.lan.length && cloudUnreachable(e)) return local(p.lan); // the QR also carries Wi-Fi addresses: use them if the internet route is down
    throw e;
  }
}
