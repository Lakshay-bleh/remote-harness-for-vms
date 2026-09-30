import { useState } from 'react';
import { describeUsage } from '@remote-harness/shared/escanor';
import { escanor, type McpInstall } from './client';
import { useLoad } from './hooks';
import { useEscanorSession } from './session';
import { ago, Button, Notice, ScreenHeader, Sheet, Spinner } from './ui';

export default function AccountView({ onOpenMachines }: { onOpenMachines: () => void }) {
  const { user, signOut } = useEscanorSession();
  const usage = useLoad(() => escanor.usage(), 60000);
  const mcp = useLoad(() => escanor.mcpConnections(), 0);
  const [install, setInstall] = useState<McpInstall | null>(null);
  const [error, setError] = useState<string | null>(null);
  const u = usage.data ? describeUsage(usage.data) : null;
  const apps = (mcp.data ?? []).filter((c) => !c.revoked_at && !c.managed_by);

  return (
    <div className="flex h-full flex-col">
    <ScreenHeader title="Account" />
    <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 py-4">
      <section className="flex items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-card font-display text-xl text-ink">{(user?.name || user?.email || '?').slice(0, 1).toUpperCase()}</div>
        <div className="min-w-0"><p className="truncate text-[17px] text-ink">{user?.name}</p><p className="truncate text-sm text-muted">{user?.email}</p></div>
      </section>

      <section>
        <h2 className="mb-2 text-sm font-medium text-ink">Today</h2>
        {usage.loading && !u ? <Spinner /> : u ? (
          <div className="rounded-lg border border-hairline p-3.5">
            <p className={`text-[15px] ${u.level === 'full' ? 'text-error' : u.level === 'warn' ? 'text-warning' : 'text-ink'}`}>{u.messages}</p>
            {u.tokens && <p className="text-[12px] text-muted">{u.tokens}</p>}
            {u.ratio !== null && <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-surface-card" role="progressbar" aria-valuenow={Math.round(u.ratio * 100)} aria-valuemin={0} aria-valuemax={100}><div className={`h-full ${u.level === 'full' ? 'bg-error' : u.level === 'warn' ? 'bg-warning' : 'bg-primary'}`} style={{ width: `${Math.round(u.ratio * 100)}%` }} /></div>}
          </div>
        ) : usage.error ? <Notice tone="error">{usage.error}</Notice> : null}
      </section>

      <section>
        <h2 className="mb-1 text-sm font-medium text-ink">Use Escanor from other AI apps</h2>
        <p className="mb-2 text-sm text-muted">Give Claude, Cursor or another AI app access to your connected services. Each gets its own key you can revoke on the web.</p>
        {error && <div className="mb-2"><Notice tone="error">{error}</Notice></div>}
        {apps.length > 0 && (
          <ul className="mb-3 divide-y divide-hairline rounded-lg border border-hairline">
            {apps.map((c) => <li key={c.id} className="flex justify-between gap-3 px-3.5 py-2.5 text-sm"><span className="truncate text-ink">{c.name}</span><span className="shrink-0 text-[12px] text-muted">{c.last_used_at ? `used ${ago(c.last_used_at)}` : 'not used yet'}</span></li>)}
          </ul>
        )}
        <Button kind="quiet" onClick={() => void escanor.createMcpInstall(`Mobile ${new Date().toLocaleDateString()}`).then((i) => { setInstall(i); mcp.reload(); }).catch((e) => setError(e.message))}>Create a key</Button>
      </section>

      <section className="space-y-2">
        <Button kind="quiet" className="w-full" onClick={onOpenMachines}>My machines</Button>
        <Button kind="danger" className="w-full" onClick={() => void signOut()}>Sign out</Button>
      </section>

      {install && (
        <Sheet title="Your new key" onClose={() => setInstall(null)}>
          <div className="space-y-3">
            <Notice tone="warn">Copy it now. It is shown only once.</Notice>
            <pre className="overflow-x-auto whitespace-pre-wrap break-all rounded-md bg-surface-dark p-3 font-mono text-[12px] text-on-dark">{install.token}</pre>
            <Button onClick={() => void navigator.clipboard?.writeText(install.token)} className="w-full">Copy key</Button>
            <p className="text-[12px] text-muted">Address: <span className="break-all font-mono">{install.endpoint}</span></p>
          </div>
        </Sheet>
      )}
    </div>
    </div>
  );
}
