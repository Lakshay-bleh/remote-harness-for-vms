/**
 * When a computer that was "offline" should be tried again, and when a failed request should count as offline at all. Pure, so it
 * is tested without a phone: the two things that made a computer that was in fact on look offline were a single failed request
 * flipping the screen, and nothing ever trying again afterwards.
 */

/** Seconds to wait before retry number `attempt` (1, 2, 3, …): quick at first, then a calm 30 s. */
export function retryDelayMs(attempt: number): number {
  return Math.min(30_000, 3_000 * 2 ** Math.max(0, attempt - 1));
}

/** A request that fails once is a hiccup (a slow poll, a changing network); two in a row means the computer is not answering. */
export const OFFLINE_AFTER_FAILURES = 2;

export const shouldShowOffline = (consecutiveFailures: number): boolean => consecutiveFailures >= OFFLINE_AFTER_FAILURES;

/** What to tell the person when the cloud route could not reach the computer, in words that point at the likely cause. */
export function offlineMessage(reason: unknown, route: 'lan' | 'cloud' | null): string {
  const text = reason instanceof Error ? reason.message : '';
  if (/session|sign in/i.test(text)) return text;
  if (route === 'cloud' || /did not answer|offline|online/i.test(text)) return 'Your computer did not answer. Check that Escanor Desktop is open and signed in, with “Away from home” on. This page keeps trying.';
  return text || 'Could not reach this computer. This page keeps trying.';
}
