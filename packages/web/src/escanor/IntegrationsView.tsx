import { Browser } from '@capacitor/browser';
import { useEffect, useMemo, useState } from 'react';
import { isNative } from '../api';
import { ApiError, escanor, type CatalogProvider } from './client';
import { useLoad } from './hooks';
import { Button, Notice, Sheet, Spinner } from './ui';

const PAGE = 30;

const fieldLabel = (f: string) => f.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());

export default function IntegrationsView() {
  const caps = useLoad(() => escanor.capabilities(), 20000);
  const catalog = useLoad(() => escanor.catalog(), 0);
  const [query, setQuery] = useState('');
  const [shown, setShown] = useState(PAGE);
  const [connecting, setConnecting] = useState<CatalogProvider | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const connected = caps.data?.integrations ?? [];
  const connectedIds = new Set(connected.map((c) => c.provider_id));
  const available = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (catalog.data ?? []).filter((p) => !connectedIds.has(p.id) && !p.connected && (!q || p.name.toLowerCase().includes(q) || p.category_label.toLowerCase().includes(q)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catalog.data, query, caps.data]);

  return (
    <div className="h-full overflow-y-auto px-4 py-4">
      <h1 className="font-display text-2xl text-ink">Connections</h1>
      <p className="mt-1 text-sm text-muted">{caps.data?.summary ?? 'What your assistant can work with.'} Connect a service once — it works here, on the web and for your assistant.</p>
      {notice && <div className="mt-3"><Notice>{notice}</Notice></div>}
      {caps.error && <div className="mt-3"><Notice tone="error">{caps.error}</Notice></div>}

      {connected.length > 0 && (
        <section className="mt-5">
          <h2 className="mb-2 text-[12px] font-medium uppercase tracking-wide text-muted">Connected</h2>
          <ul className="divide-y divide-hairline rounded-lg border border-hairline">
            {connected.map((c) => (
              <li key={c.provider_id} className="flex items-center justify-between gap-3 px-3.5 py-3">
                <div className="min-w-0">
                  <p className="truncate text-[15px] text-ink">{c.name}</p>
                  <p className={`text-[12px] ${c.needs_reconnect ? 'text-warning' : c.available_to_assistant ? 'text-success' : 'text-muted'}`}>
                    {c.needs_reconnect ? 'Needs reconnecting' : c.available_to_assistant ? 'Your assistant can use this' : c.available_to_assistant === false ? 'Connected — no assistant tools for it yet' : 'Connected'}
                  </p>
                </div>
                <button
                  onClick={() => { if (window.confirm(`Disconnect ${c.name}? Your assistant will no longer be able to use it.`)) void escanor.disconnect(c.provider_id).then(() => { setNotice(`${c.name} disconnected.`); caps.reload(); }).catch((e) => setNotice(e.message)); }}
                  className="shrink-0 rounded-md px-2.5 py-1.5 text-sm text-muted hover:text-error"
                >
                  Disconnect
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="mt-6">
        <h2 className="mb-2 text-[12px] font-medium uppercase tracking-wide text-muted">Add a service</h2>
        <input value={query} onChange={(e) => { setQuery(e.target.value); setShown(PAGE); }} placeholder="Search GitHub, Vercel, Sentry…" aria-label="Search services" className="mb-3 w-full rounded-md border border-hairline px-3.5 py-2.5 text-base outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
        {catalog.loading && <Spinner />}
        {catalog.error && <Notice tone="error">{catalog.error}</Notice>}
        <ul className="divide-y divide-hairline rounded-lg border border-hairline">
          {available.slice(0, shown).map((p) => (
            <li key={p.id}>
              <button onClick={() => setConnecting(p)} className="flex w-full items-center justify-between gap-3 px-3.5 py-3 text-left hover:bg-surface-card">
                <span className="min-w-0"><span className="block truncate text-[15px] text-ink">{p.name}</span><span className="block truncate text-[12px] text-muted">{p.category_label}</span></span>
                <span className="shrink-0 text-sm text-primary">Connect</span>
              </button>
            </li>
          ))}
          {!catalog.loading && available.length === 0 && <li className="px-3.5 py-3 text-sm text-muted">Nothing matches.</li>}
        </ul>
        {available.length > shown && <Button kind="quiet" className="mt-3 w-full" onClick={() => setShown((n) => n + PAGE)}>Show more</Button>}
      </section>

      {connecting && <ConnectSheet provider={connecting} onClose={() => setConnecting(null)} onConnected={(name) => { setConnecting(null); setNotice(`${name} connected.`); caps.reload(); }} />}
    </div>
  );
}

function ConnectSheet({ provider, onClose, onConnected }: { provider: CatalogProvider; onClose: () => void; onConnected: (name: string) => void }) {
  const [token, setToken] = useState('');
  const [fields, setFields] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [waiting, setWaiting] = useState(false);

  const viaKey = provider.connect_via === 'api_key' || provider.connect_via === 'credentials';
  const viaOauth = provider.connect_via === 'oauth' && provider.oauth_available;

  // After the browser step, the backend records the connection on its own; watch for it.
  useEffect(() => {
    if (!waiting) return;
    const started = Date.now();
    const timer = setInterval(async () => {
      try {
        const now = await escanor.capabilities();
        if (now.integrations.some((i) => i.provider_id === provider.id)) onConnected(provider.name);
      } catch { /* keep waiting */ }
      if (Date.now() - started > 120_000) { setWaiting(false); setError('That took too long. Try again.'); }
    }, 2000);
    return () => clearInterval(timer);
  }, [waiting, provider, onConnected]);

  async function submitKey() {
    setBusy(true);
    setError(null);
    try {
      await escanor.connectWithKey(provider.id, { access_token: token.trim() || undefined, credentials: Object.keys(fields).length ? fields : undefined });
      onConnected(provider.name);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not connect.');
    } finally {
      setBusy(false);
    }
  }

  async function startOauth() {
    setBusy(true);
    setError(null);
    try {
      const url = await escanor.integrationAuthorizeUrl(provider.id);
      setWaiting(true);
      if (isNative()) await Browser.open({ url });
      else window.open(url, '_blank', 'noopener');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Sheet title={`Connect ${provider.name}`} onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-body">{provider.description}</p>
        {error && <Notice tone="error">{error}</Notice>}
        {provider.connect_via === 'local_agent' && <Notice>{provider.name} connects through a machine you pair. Set it up from Local Hub in Escanor on the web.</Notice>}
        {viaOauth && (
          <>
            <Button onClick={() => void startOauth()} disabled={busy || waiting} className="w-full">{waiting ? 'Waiting for you to finish…' : `Continue with ${provider.name}`}</Button>
            {waiting && <p className="flex items-center gap-2 text-[12px] text-muted"><Spinner /> Finish in the browser, then come back here.</p>}
          </>
        )}
        {viaKey && (
          <form onSubmit={(e) => { e.preventDefault(); void submitKey(); }} className="space-y-3">
            <label className="block text-sm text-body">
              {provider.token_label}
              <input type="password" autoComplete="off" value={token} onChange={(e) => setToken(e.target.value)} className="mt-1 w-full rounded-md border border-hairline px-3.5 py-2.5 text-base outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
            </label>
            {provider.credential_fields.map((f) => (
              <label key={f} className="block text-sm text-body">
                {fieldLabel(f)}
                <input value={fields[f] ?? ''} onChange={(e) => setFields((s) => ({ ...s, [f]: e.target.value }))} autoComplete="off" className="mt-1 w-full rounded-md border border-hairline px-3.5 py-2.5 text-base outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
              </label>
            ))}
            {provider.help_url && <a href={provider.help_url} target="_blank" rel="noreferrer noopener" className="block text-[12px] text-primary underline">Where do I find this?</a>}
            <Button type="submit" disabled={busy || (!token.trim() && provider.credential_fields.every((f) => !fields[f]?.trim()))} className="w-full">{busy ? 'Connecting…' : 'Connect'}</Button>
          </form>
        )}
        {!viaKey && !viaOauth && provider.connect_via !== 'local_agent' && <Notice>{provider.name} can’t be connected from here yet.</Notice>}
      </div>
    </Sheet>
  );
}
