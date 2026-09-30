import { CopyRow } from '../components/EscanorConnect';
import { useManagedHub } from './ManagedMachines';
import { Notice, Sheet } from './ui';

/** How to put the agent on a VM, with this person's hub address and secret already filled in. */
export function ConnectMachineSheet({ onClose }: { onClose: () => void }) {
  const hub = useManagedHub();
  if (!hub) return null;
  return (
    <Sheet title="Connect a machine" onClose={onClose}>
      <div className="space-y-4 pb-2">
        <p className="text-sm text-body">Run this on the server you want to control. It installs the agent and points it at your hub, so it appears here as soon as it starts.</p>
        {hub.install_command && <CopyRow label="Run on your VM" value={hub.install_command} secret />}
        <details className="rounded-md border border-hairline px-3 py-2">
          <summary className="cursor-pointer text-[13px] text-muted">Prefer to enter them yourself?</summary>
          <div className="mt-3 space-y-3">
            {hub.agent_url && <CopyRow label="Hub URL" value={hub.agent_url} />}
            {hub.agent_token && <CopyRow label="Secret" value={hub.agent_token} secret />}
          </div>
        </details>
        <Notice tone="warn">The secret lets a machine join your hub. Keep it to yourself; it works for your machines only.</Notice>
        {hub.guide_url && (
          <a href={hub.guide_url} target="_blank" rel="noreferrer noopener" className="block rounded-md bg-primary px-4 py-2.5 text-center text-sm font-medium text-on-primary transition hover:bg-primary-active">
            Read the setup guide
          </a>
        )}
      </div>
    </Sheet>
  );
}
