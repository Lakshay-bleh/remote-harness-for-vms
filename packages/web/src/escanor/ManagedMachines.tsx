import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { useStore } from '../store';
import { escanor } from './client';
import { useLoad } from './hooks';
import { applyManaged, type ManagedHub } from './managed';
import { Button, Notice, Spinner } from './ui';

const ManagedHubContext = createContext<ManagedHub | null>(null);

/** The signed-in person's hosted hub, when the machines screen is showing it; null on a self-hosted hub. */
export const useManagedHub = (): ManagedHub | null => useContext(ManagedHubContext);

/**
 * The machines screen for someone signed in to Escanor. The hub address and their token come from Escanor
 * (created for them the first time), so there is no hub to deploy and no password to type. If this Escanor
 * has no hosted hub, `fallback` -- the self-hosted flow -- is shown instead.
 */
export default function ManagedMachines({ children, fallback }: { children: ReactNode; fallback: ReactNode }) {
  const { actions } = useStore();
  const hub = useLoad(() => escanor.managedHub(), 0);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!hub.data?.available) return;
    const rotated = applyManaged(hub.data);
    // A rotated token means the open connection is dead; starting over is the simplest way to be sure.
    if (rotated) return window.location.reload();
    actions.dispatch({ type: 'set_authed', authed: true });
    setReady(true);
  }, [hub.data, actions]);

  // The hub refused our token (it was rotated elsewhere): ask Escanor for the current one.
  useEffect(() => {
    window.addEventListener('rh-managed-unauthorized', hub.reload);
    return () => window.removeEventListener('rh-managed-unauthorized', hub.reload);
  }, [hub.reload]);

  if (hub.data && !hub.data.available) return <>{fallback}</>;
  if (hub.error && !hub.data) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
        <Notice tone="error">{hub.error}</Notice>
        <Button kind="quiet" onClick={hub.reload}>Try again</Button>
      </div>
    );
  }
  if (!ready || !hub.data) return <div className="flex h-full items-center justify-center"><Spinner /></div>;
  return <ManagedHubContext.Provider value={hub.data}>{children}</ManagedHubContext.Provider>;
}
