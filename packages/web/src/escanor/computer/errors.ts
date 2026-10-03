/** Where the fix is: on this phone, on the computer, or on both. */
export type FixWhere = 'phone' | 'computer' | 'both';

export interface Explained {
  /** What happened, in one line. */
  title: string;
  where: FixWhere;
  /** What to do, in order. Each step says which device it is on. */
  steps: string[];
  /** If the failure is "this is switched off for phones", the group's label: the phone can offer to ask the computer to allow it. */
  ask?: { groupLabel: string };
}

const text = (e: unknown): string => (e instanceof Error ? e.message : typeof e === 'string' ? e : '');

/**
 * Turn what failed into: what happened, where to change it (this app or Escanor Desktop), and the steps. No error in the app is
 * allowed to say "enable it in settings" without saying which settings: this is where that is enforced.
 */
export function explainFailure(raw: unknown): Explained {
  const m = text(raw).trim();

  const off = /^[“"](.+?)[”"] is turned off for (phones|Escanor’s voice assistant)/.exec(m);
  if (off) {
    const phones = off[2] === 'phones';
    return {
      title: `“${off[1]}” is switched off for ${phones ? 'phones' : 'voice'}`,
      where: 'computer',
      steps: [`On your computer: open Escanor Desktop → Settings → Permissions.`, `Find “${off[1]}” and switch it on in the ${phones ? 'Phone' : 'Escanor (voice)'} column.`, 'Then try again here.'],
      ...(phones ? { ask: { groupLabel: off[1] } } : {}),
    };
  }

  if (/too old for that|Update Escanor Desktop/i.test(m)) {
    return { title: 'Your computer’s Escanor Desktop is out of date', where: 'computer', steps: ['Update Escanor Desktop on your computer to the latest version, then reopen it.', 'Then try again here.'] };
  }

  if (/session ended|sign in again|not signed in/i.test(m)) {
    return { title: 'You were signed out of Escanor', where: 'phone', steps: ['In this app: open Settings → Account and sign in again.'] };
  }

  if (m === 'Not allowed.' || /no longer paired|not paired|revoked|That is not your computer/i.test(m)) {
    return {
      title: 'This computer no longer recognises this phone',
      where: 'both',
      steps: ['On your computer: open Escanor Desktop → Phone → Pair a phone.', 'In this app: remove this computer (menu at the top right), then add it again with the new code.'],
    };
  }

  if (/did not answer|not reachable|could not reach|offline|timed out|not on and online/i.test(m)) {
    return {
      title: 'Your computer is not answering',
      where: 'computer',
      steps: ['On your computer: make sure Escanor Desktop is open and signed in to the same account.', 'In Escanor Desktop → Phone: turn on “Away from home”, or be on the same Wi-Fi as this phone.', 'Then tap Try again here.'],
    };
  }

  if (/pair|code/i.test(m) && /expired|not showing|did not match|No pairing/i.test(m)) {
    return { title: 'That pairing code did not work', where: 'computer', steps: ['On your computer: open Escanor Desktop → Phone → Pair a phone to get a fresh code (it lasts 5 minutes and works once).', 'In this app: enter the new code.'] };
  }

  return { title: m || 'That did not work', where: 'both', steps: ['Try again. If it keeps failing, check that Escanor Desktop is open on your computer and that both are signed in to the same account.'] };
}
