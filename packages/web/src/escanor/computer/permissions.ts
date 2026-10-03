import type { GroupRequestStatus, PermissionGroup } from './lib/protocol';

/** What to tell the person once the computer has answered "may phones use this?". Says where the question is, and what to do. */
export function describeGroupRequest(status: GroupRequestStatus, label: string): string {
  switch (status) {
    case 'asked':
      return `Asked. A question just appeared in Escanor Desktop on your computer: “Let your phones use ${label}?”. Choose Allow there. This list updates by itself.`;
    case 'unavailable':
      return 'Open Escanor Desktop on your computer first (it needs its window open to ask you), then ask again.';
    case 'already_on':
      return `“${label}” is already allowed for phones.`;
    case 'busy':
      return `Your computer has already been asked about “${label}” and is waiting for your answer there.`;
    default:
      return 'Your computer does not recognise that. Update Escanor Desktop on it, then try again.';
  }
}

const norm = (s: string) => s.replace(/[“”"]/g, '').trim().toLowerCase();

export const findGroup = (groups: PermissionGroup[], label: string): PermissionGroup | undefined => groups.find((g) => norm(g.label) === norm(label));

/** Switched off first (that is what someone opens this to fix), then alphabetical. A new list: the input is untouched. */
export const sortGroups = (groups: PermissionGroup[]): PermissionGroup[] => [...groups].sort((a, b) => Number(a.enabled) - Number(b.enabled) || a.label.localeCompare(b.label));
