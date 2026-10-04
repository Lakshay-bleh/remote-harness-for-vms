import { POLICY_VERSION } from '../../legal/content';
import { escanor } from '../client';
import { setVoicePrefs } from './voicePrefs';

const PENDING = 'escanor.controlConsent.pending';

/** Send the latest phone-control choice to the consent ledger. A choice that could not be sent waits here for the next try. */
async function send(grant: boolean, record: (grant: boolean) => Promise<unknown>): Promise<void> {
  try {
    await record(grant);
    localStorage.removeItem(PENDING);
  } catch {
    try {
      localStorage.setItem(PENDING, grant ? 'grant' : 'withdraw');
    } catch {
      // kept for this visit only
    }
  }
}

const toLedger = (grant: boolean) => escanor.recordConsent('phone_control', grant, POLICY_VERSION);

/** The person agreed to (or took back) phone control: remember it on the phone at once, and in their account's consent ledger. */
export function setControlConsent(grant: boolean, record: (grant: boolean) => Promise<unknown> = toLedger): Promise<void> {
  setVoicePrefs({ controlConsent: grant });
  return send(grant, record);
}

/** Send a choice that could not be sent before (offline, signed out). Does nothing when none is waiting. */
export async function flushControlConsent(record: (grant: boolean) => Promise<unknown> = toLedger): Promise<void> {
  let pending: string | null = null;
  try {
    pending = localStorage.getItem(PENDING);
  } catch {
    return;
  }
  if (pending === 'grant' || pending === 'withdraw') await send(pending === 'grant', record);
}
