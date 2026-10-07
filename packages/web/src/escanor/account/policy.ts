import type { ConsentState } from './privacy';

export const ACCEPTANCE_PURPOSES = ['terms', 'privacy_notice'] as const;
const RULES_NOTICE_EVERY_MS = 90 * 24 * 3_600_000;

/** True until both acceptance records exist at the current policy version. */
export function needsAcceptance(states: ConsentState[], version: string): boolean {
  return ACCEPTANCE_PURPOSES.some((purpose) => {
    const found = states.find((s) => s.purpose === purpose);
    return !found || !found.granted || found.notice_version !== version;
  });
}

/** The IT Rules ask that people are reminded of the rules at least every three months. */
export function needsRulesNotice(states: ConsentState[], now: Date = new Date()): boolean {
  const found = states.find((s) => s.purpose === 'rules_notice');
  return !found || now.getTime() - new Date(found.recorded_at).getTime() > RULES_NOTICE_EVERY_MS;
}
