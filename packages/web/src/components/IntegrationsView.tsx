import { useEffect, useMemo, useState } from 'react';
import { useEscanor } from '../escanor/EscanorProvider';
import PageShell from './PageShell';

export default function IntegrationsView({ className, onMenu }: { className: string; onMenu: () => void }) {
  const { session, catalog, connections, catalogError, notice, dismissNotice, signInWithGoogle, connectProvider, refreshIntegrations } = useEscanor();
  const [query, setQuery] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (session) void refreshIntegrations();
  }, [session]);

  const connected = useMemo(() => new Set(connections.filter((c) => c.isActive).map((c) => c.providerId)), [connections]);
  const q = query.trim().toLowerCase();

  async function connect(id: string) {
    setBusyId(id);
    setError(null);
    try {
      await connectProvider(id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start the connection');
    } finally {
      setBusyId(null);
    }
  }

  return (
    <PageShell title="Integrations" onMenu={onMenu} className={className}>
      <div className="mx-auto max-w-2xl px-4 py-5">
        {notice && (
          <div className="mb-4 flex items-start justify-between gap-3 rounded-md border border-hairline bg-surface-soft px-3 py-2 text-[13px] text-body">
            <span>{notice}</span>
            <button onClick={dismissNotice} className="text-muted-soft">×</button>
          </div>
        )}

        {!session ? (
          <div className="rounded-xl border border-hairline bg-surface-soft p-6 text-center">
            <p className="text-[15px] font-medium text-ink">Sign in to manage integrations</p>
            <p className="mt-1 text-[13px] text-muted">Integrations are tied to your Escanor account.</p>
            <button onClick={() => void signInWithGoogle().catch((e) => setError(e.message))} className="mt-4 rounded-md bg-primary px-4 py-2.5 text-sm font-medium text-on-primary hover:bg-primary-active">
              Continue with Google
            </button>
            {error && <p className="mt-3 text-sm text-error">{error}</p>}
          </div>
        ) : (
          <>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search integrations"
              className="mb-5 w-full rounded-md border border-hairline bg-canvas px-3 py-2 text-base text-ink outline-none placeholder:text-muted-soft focus:border-primary md:text-[13px]"
            />
            {(error || catalogError) && <p className="mb-4 text-sm text-error">{error ?? catalogError}</p>}
            {!catalog && !catalogError && <p className="text-sm text-muted-soft">Loading…</p>}
            {catalog?.map((cat) => {
              const providers = cat.providers.filter((p) => !q || p.name.toLowerCase().includes(q) || p.description.toLowerCase().includes(q));
              if (providers.length === 0) return null;
              return (
                <section key={cat.id} className="mb-6">
                  <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wide text-muted-soft">{cat.label}</h3>
                  <div className="overflow-hidden rounded-xl border border-hairline">
                    {providers.map((p, i) => {
                      const isConnected = connected.has(p.id);
                      const stub = p.implementationStatus === 'stub';
                      return (
                        <div key={p.id} className={`flex items-center gap-3 bg-canvas px-4 py-3 ${i > 0 ? 'border-t border-hairline' : ''}`}>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[14px] font-medium text-ink">{p.name}</p>
                            <p className="truncate text-[12px] text-muted-soft">{p.description}</p>
                          </div>
                          {isConnected ? (
                            <span className="rounded-full bg-success/15 px-2.5 py-1 text-[12px] font-medium text-success">Connected</span>
                          ) : stub ? (
                            <span className="text-[12px] text-muted-soft">Coming soon</span>
                          ) : p.supportsOauth ? (
                            <button
                              disabled={busyId === p.id}
                              onClick={() => void connect(p.id)}
                              className="rounded-md border border-hairline px-3 py-1.5 text-[13px] text-ink transition hover:bg-surface-card disabled:opacity-50"
                            >
                              {busyId === p.id ? 'Opening…' : 'Connect'}
                            </button>
                          ) : (
                            <span className="text-[12px] text-muted-soft">Set up on web</span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </section>
              );
            })}
          </>
        )}
      </div>
    </PageShell>
  );
}
