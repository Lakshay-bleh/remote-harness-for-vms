import { getToken, setHubUrl, setToken } from '../api';

/**
 * Escanor's hosted hub. Signing in to Escanor gives the person a private tenant on it: the backend hands the
 * app the hub's address and a token that belongs to that person alone, and the same hub serves everyone else
 * on their own tokens. The app keeps them where the self-hosted flow keeps a hub login, so the machines
 * screen works the same either way -- plus a flag, so signing out of Escanor takes them away again.
 */
export interface ManagedHub {
  available: boolean;
  hub_url?: string;
  /** wss://…/agent, what a VM's agent dials. */
  agent_url?: string;
  /** The secret a VM's agent authenticates with. */
  agent_token?: string;
  app_token?: string;
  /** One line to run on a VM: installs the agent already pointed at this hub. */
  install_command?: string;
  guide_url?: string;
}

const FLAG = 'rh_managed';

export const isManaged = (): boolean => localStorage.getItem(FLAG) === '1';

/** Point this app at the person's hosted tenant. Returns true if the token changed (it was rotated). */
export function applyManaged(hub: ManagedHub): boolean {
  const changed = isManaged() && getToken() !== hub.app_token;
  setHubUrl(hub.hub_url ?? '');
  setToken(hub.app_token ?? null);
  localStorage.setItem(FLAG, '1');
  return changed;
}

/** Forget the hosted tenant's credentials (Escanor sign-out). Returns true if there were any. */
export function clearManaged(): boolean {
  if (!isManaged()) return false;
  setToken(null);
  setHubUrl('');
  localStorage.removeItem(FLAG);
  return true;
}
