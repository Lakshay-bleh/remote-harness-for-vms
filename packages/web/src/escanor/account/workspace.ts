/** Workspace and team presentation, pure so it can be tested. */

export const REGIONS = [
  { value: 'auto', label: 'Automatic' },
  { value: 'us-east', label: 'US East' },
  { value: 'us-west', label: 'US West' },
  { value: 'eu-west', label: 'Europe West' },
  { value: 'ap-south', label: 'India and South Asia' },
  { value: 'ap-southeast', label: 'Southeast Asia' },
] as const;

export const ENVIRONMENTS = [
  { value: 'production', label: 'Production' },
  { value: 'staging', label: 'Staging' },
  { value: 'development', label: 'Development' },
] as const;

const label = (list: ReadonlyArray<{ value: string; label: string }>, v: string) => list.find((o) => o.value === v)?.label ?? v;
export const regionLabel = (v: string) => label(REGIONS, v);
export const environmentLabel = (v: string) => label(ENVIRONMENTS, v);

/** A workspace name as the server will accept it: one line, 1 to 80 characters. Null when it is not usable. */
export function cleanWorkspaceName(text: string): string | null {
  const name = text.replace(/\s+/g, ' ').trim();
  return name.length >= 1 && name.length <= 80 ? name : null;
}

/** "workspace.settings_updated" -> "Workspace settings updated"; unknown shapes stay readable. */
export function describeAction(action: string): string {
  const words = action.replace(/[._]+/g, ' ').trim();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : 'Activity';
}

export const roleLabel = (role: string) => (role === 'owner' ? 'Owner' : role === 'admin' ? 'Admin' : 'Member');

export const ACTIVITY_PAGE = 25;
export const ACTIVITY_MAX = 500; // what the server will return

/** The part of an action before the first dot: "billing.plan_changed" is "billing". */
export const actionGroup = (action: string): string => (action.split('.')[0] || 'other').toLowerCase();

/** The kinds of activity present in a list, most frequent first, for the filter chips. */
export function activityGroups(lines: ReadonlyArray<{ action: string }>): { value: string; label: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const l of lines) counts.set(actionGroup(l.action), (counts.get(actionGroup(l.action)) ?? 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([value, count]) => ({ value, label: describeAction(value), count }));
}

/** Lines of one kind (or all), whose action, person, target or detail contains the text. */
export function filterActivity<T extends { action: string; actor_email: string | null; target: string; detail: string }>(lines: readonly T[], o: { group: string | null; query: string }): T[] {
  const q = o.query.trim().toLowerCase();
  return lines.filter((l) => (!o.group || actionGroup(l.action) === o.group) && (!q || [describeAction(l.action), l.actor_email, l.target, l.detail].some((f) => (f ?? '').toLowerCase().includes(q))));
}

/** Whether asking for more could return more: the last answer filled the request and the server's ceiling is not reached. */
export const canLoadMore = (received: number, asked: number): boolean => received >= asked && asked < ACTIVITY_MAX;
export const nextActivityLimit = (asked: number): number => Math.min(ACTIVITY_MAX, asked + ACTIVITY_PAGE * 2);
