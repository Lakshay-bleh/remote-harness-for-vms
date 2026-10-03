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
