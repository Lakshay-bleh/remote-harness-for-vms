import type { ConsentState } from './privacy';

export const ACCEPTANCE_PURPOSES = ['terms', 'privacy_notice'] as const;
const RULES_NOTICE_EVERY_MS = 90 * 24 * 3_600_000;

/**
 * True until both acceptance records exist at the current policy version or a newer one. Versions are dates (YYYY-MM-DD), so
 * they order as strings. A newer one counts because the website, the desktop app and this app write the same records: if
 * only the exact version counted, two apps on different versions would each ask again after the other had recorded its own.
 */
export function needsAcceptance(states: ConsentState[], version: string): boolean {
  return ACCEPTANCE_PURPOSES.some((purpose) => {
    const found = states.find((s) => s.purpose === purpose);
    return !found || !found.granted || found.notice_version < version;
  });
}

/** The IT Rules ask that people are reminded of the rules at least every three months. */
export function needsRulesNotice(states: ConsentState[], now: Date = new Date()): boolean {
  const found = states.find((s) => s.purpose === 'rules_notice');
  return !found || now.getTime() - new Date(found.recorded_at).getTime() > RULES_NOTICE_EVERY_MS;
}
