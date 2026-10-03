/** Two-step verification and deleting an account: the rules the screens follow, kept where they can be tested. */

/** A code as typed: six digits (spaces are fine), or a backup code like ABCD-EFGH. Returns what to send, or null if it is neither. */
export function parseCodeInput(text: string): string | null {
  const digits = text.replace(/\s+/g, '');
  if (/^\d{6}$/.test(digits)) return digits;
  const backup = text.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return /^[A-Z2-9]{8}$/.test(backup) ? `${backup.slice(0, 4)}-${backup.slice(4)}` : null;
}

/** Typing the account email is the "are you sure": exact, but not fussy about case or stray spaces. */
export const emailConfirmed = (typed: string, email: string | null | undefined): boolean => Boolean(email) && typed.trim().toLowerCase() === String(email).trim().toLowerCase();

/** "in 6 days", "in 5 hours", "today": how long until the date, for "your account will be deleted …". */
export function daysUntil(iso: string, now: Date = new Date()): string {
  const diff = new Date(iso).getTime() - now.getTime();
  if (Number.isNaN(diff)) return '';
  if (diff <= 0) return 'now';
  const days = Math.floor(diff / 86_400_000);
  if (days >= 1) return `in ${days} day${days === 1 ? '' : 's'}`;
  const hours = Math.max(1, Math.floor(diff / 3_600_000));
  return `in ${hours} hour${hours === 1 ? '' : 's'}`;
}

/** What the server does not do for the person, said before they confirm: shown as the list on the delete screen. */
export const DELETION_FACTS = [
  'You are signed out everywhere and every key you made stops working straight away.',
  'After 7 days your account and everything in it is deleted: connected services, chats, machines, keys and plans. A subscription is cancelled.',
  'If you sign in during those 7 days you can cancel the deletion.',
  'A few records are kept because the law asks for them: your consent history and privacy requests (without your contact details) and the audit trail.',
] as const;
