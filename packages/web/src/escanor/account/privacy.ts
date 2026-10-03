/** Privacy choices and requests, as the app shows them. The wording and rules follow the website's Privacy panel, so a person sees the same thing in both. */

export interface ConsentState {
  purpose: string;
  granted: boolean;
  notice_version: string;
  recorded_at: string;
}

/** Separate, optional consents. None is bundled into another or needed to use the service. */
export const OPTIONAL_CONSENTS = [
  { purpose: 'marketing', label: 'Product news and offers', description: 'Occasional emails about new features and offers. Not needed to use Escanor.' },
  { purpose: 'product_updates', label: 'Product update notices', description: 'Notices about changes to the product that are not required service messages.' },
  { purpose: 'analytics', label: 'Usage analytics', description: 'Allow measuring how features are used so they can be improved. Not needed to use Escanor.' },
  { purpose: 'ai_improvement', label: 'Use my content to improve AI features', description: 'Allow prompts and results to be used to evaluate and improve AI features. Off unless you turn it on.' },
] as const;

export const REQUEST_TYPES = [
  { value: 'access', label: 'Get a copy of my data', hint: 'You can also copy it straight from here.' },
  { value: 'correction', label: 'Correct my data', hint: 'Something about you is wrong.' },
  { value: 'consent_withdrawal', label: 'Withdraw a consent', hint: 'Or switch it off above, which takes effect at once.' },
  { value: 'nomination', label: 'Nominate someone to act for me', hint: 'Someone who may act if you cannot.' },
  { value: 'grievance', label: 'Make a complaint or report a problem', hint: 'It is tracked and answered within the legal deadline.' },
  { value: 'erasure', label: 'Delete my data (without deleting the account)', hint: 'To delete the whole account, use Delete account in Security.' },
] as const;

export type RequestType = (typeof REQUEST_TYPES)[number]['value'];

const STATUS_LABELS: Record<string, string> = { received: 'Received', acknowledged: 'Acknowledged', in_progress: 'In progress', escalated: 'Escalated', fulfilled: 'Completed', rejected: 'Declined' };
export const statusLabel = (status: string): string => STATUS_LABELS[status] ?? status;
export const isFinished = (status: string): boolean => status === 'fulfilled' || status === 'rejected';

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const plural = (n: number, unit: string) => `${n} ${unit}${n === 1 ? '' : 's'}`;

/** "due in 2 days", "due in 5 hours", "overdue by 1 day". */
export function describeDue(iso: string, now: Date = new Date()): string {
  const diff = new Date(iso).getTime() - now.getTime();
  if (Number.isNaN(diff)) return '';
  const abs = Math.abs(diff);
  const text = abs >= DAY ? plural(Math.floor(abs / DAY), 'day') : plural(Math.max(1, Math.floor(abs / HOUR)), 'hour');
  return diff >= 0 ? `due in ${text}` : `overdue by ${text}`;
}

export interface RequestDraft {
  request_type: RequestType;
  subject: string;
  details: string;
}

/** The first thing wrong with a request, in words, or null. The limits are the server's (subject 3 to 200 characters, details up to 5000). */
export function requestProblem(d: RequestDraft): string | null {
  const subject = d.subject.trim();
  if (subject.length < 3) return 'Give it a short title (at least 3 characters).';
  if (subject.length > 200) return 'Make the title shorter (200 characters at most).';
  if (d.details.length > 5000) return 'The details are too long (5,000 characters at most).';
  return null;
}
