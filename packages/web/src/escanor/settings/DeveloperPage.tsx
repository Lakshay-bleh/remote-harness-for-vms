import { ArrowsClockwise, Bug, Copy, Globe, Key, Plugs, Trash } from '@phosphor-icons/react';
import { useState } from 'react';
import { isNative } from '../../api';
import { APP_VERSION } from '../../appInfo';
import { escanor, type McpInstall } from '../client';
import { clearComputers, loadComputers } from '../computer/storage';
import { escanorApiBase, setEscanorApiBase } from '../config';
import { useLoad } from '../hooks';
import { LINKS, openExternal } from '../links';
import { useEscanorSession } from '../session';
import { ago, Button, Notice, Sheet, Spinner } from '../ui';
import { checkApiUrl } from './apiUrl';
import { ConfirmSheet, Group, Page, Row } from './parts';
import { resetPrefs } from './prefs';

const DEFAULT_HOST = 'api.escanor.in';
const host = (url: string) => { try { return new URL(url).host; } catch { return url; } };

type Check = { state: 'idle' } | { state: 'running' } | { state: 'done'; ok: boolean; ms: number; status: number };

/** For people who build on Escanor: where the app connects, whether it can reach it, keys for other AI apps, and what to send when asking for help. */
export default function DeveloperPage({ onBack }: { onBack: () => void }) {
  const { user } = useEscanorSession();
  const mcp = useLoad(() => escanor.mcpConnections(), 0);
  const apps = (mcp.data ?? []).filter((c) => !c.revoked_at && !c.managed_by);
  const [check, setCheck] = useState<Check>({ state: 'idle' });
  const [install, setInstall] = useState<McpInstall | null>(null);
  const [creating, setCreating] = useState(false);
  const [keyError, setKeyError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [editServer, setEditServer] = useState(false);
  const [serverText, setServerText] = useState('');
  const [serverError, setServerError] = useState<string | null>(null);
  const [confirmServer, setConfirmServer] = useState<string | null>(null);
  const [confirmReset, setConfirmReset] = useState(false);
  const api = escanorApiBase();
  const custom = host(api) !== DEFAULT_HOST;

  const copy = async (what: string, text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(what);
      setTimeout(() => setCopied((c) => (c === what ? null : c)), 2000);
    } catch {
      setCopied(null);
    }
  };

  const runCheck = async () => {
    setCheck({ state: 'running' });
    setCheck({ state: 'done', ...(await escanor.ping()) });
  };

  const debugInfo = () =>
    [
      `Escanor app ${APP_VERSION}`,
      `Platform: ${isNative() ? 'Android app' : 'browser'}`,
      `Server: ${api}${custom ? ' (custom)' : ''}`,
      `Signed in: ${user ? 'yes' : 'no'}`,
      `Paired computers: ${loadComputers().length}`,
      `Screen: ${window.innerWidth}x${window.innerHeight} @${window.devicePixelRatio}x`,
      `Online: ${navigator.onLine}`,
      `User agent: ${navigator.userAgent}`,
      `Time: ${new Date().toISOString()}`,
    ].join('\n');

  const createKey = async () => {
    setCreating(true);
    setKeyError(null);
    try {
      setInstall(await escanor.createMcpInstall(`Mobile ${new Date().toLocaleDateString()}`));
      mcp.reload();
    } catch (e) {
      setKeyError(e instanceof Error ? e.message : 'Could not create a key.');
    } finally {
      setCreating(false);
    }
  };

  const applyServer = () => {
    const r = checkApiUrl(serverText);
    if (!r.ok) return setServerError(r.reason);
    setServerError(null);
    setEditServer(false);
    setConfirmServer(r.url);
  };

  return (
    <Page title="Developer" subtitle="For building on Escanor and asking for help" onBack={onBack}>
      <Group title="Connection" footer="This is the server the app talks to. Test checks that it answers; it does not need you to be signed in.">
        <Row icon={<Globe size={18} />} label="Server" value={host(api)} sub={custom ? 'Custom: not the Escanor default' : undefined} onClick={() => { setServerText(custom ? api : ''); setServerError(null); setEditServer(true); }} />
        <Row
          icon={<Plugs size={18} />}
          label="Test connection"
          onClick={() => void runCheck()}
          chevron={false}
          disabled={check.state === 'running'}
          value={check.state === 'running' ? <Spinner /> : check.state === 'done' ? <span className={check.ok ? 'text-success' : 'text-error'}>{check.ok ? `Reachable · ${check.ms} ms` : check.status ? `Error ${check.status}` : 'Cannot reach it'}</span> : undefined}
        />
      </Group>

      <section>
        <h2 className="mb-1 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Keys for other AI apps</h2>
        <p className="mb-2 px-1 text-[12px] leading-relaxed text-muted">Give Claude, Cursor or another AI app access to your connected services. Each gets its own key, which you can revoke on the website.</p>
        {keyError && <div className="mb-2"><Notice tone="error">{keyError}</Notice></div>}
        <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
          {mcp.loading && !mcp.data ? <div className="p-4 text-center"><Spinner /></div> : apps.length === 0 ? (
            <p className="px-3.5 py-3 text-sm text-muted">No keys yet.</p>
          ) : (
            apps.map((c) => <Row key={c.id} icon={<Key size={18} />} label={c.name} sub={`${c.total_calls.toLocaleString()} calls`} value={c.last_used_at ? `used ${ago(c.last_used_at)}` : 'not used yet'} />)
          )}
          <Row icon={<Key size={18} />} label={creating ? 'Creating…' : 'Create a key'} onClick={() => void createKey()} disabled={creating} />
        </div>
      </section>

      <Group title="Help and diagnostics" footer="The debug details contain no passwords or tokens.">
        <Row icon={<Copy size={18} />} label="Copy debug info" value={copied === 'debug' ? 'Copied' : undefined} onClick={() => void copy('debug', debugInfo())} chevron={false} />
        <Row icon={<Bug size={18} />} label="Report a problem" onClick={() => openExternal(LINKS.support)} />
        <Row icon={<ArrowsClockwise size={18} />} label="Reload the app" onClick={() => window.location.reload()} chevron={false} />
      </Group>

      <Group title="This phone" footer="Removes saved preferences, the server override and the computers paired with this phone. You stay signed in.">
        <Row icon={<Trash size={18} />} label="Reset app data" danger onClick={() => setConfirmReset(true)} />
      </Group>
      <p className="text-center text-[12px] text-muted-soft">Version {APP_VERSION}</p>

      {install && (
        <Sheet title="Your new key" onClose={() => setInstall(null)}>
          <div className="space-y-3">
            <Notice tone="warn">Copy it now. It is shown only once.</Notice>
            <pre className="overflow-x-auto whitespace-pre-wrap break-all rounded-md bg-surface-dark p-3 font-mono text-[12px] text-on-dark">{install.token}</pre>
            <Button onClick={() => void copy('key', install.token)} className="w-full">{copied === 'key' ? 'Copied' : 'Copy key'}</Button>
            <p className="text-[12px] text-muted">Address: <span className="break-all font-mono">{install.endpoint}</span></p>
          </div>
        </Sheet>
      )}

      {editServer && (
        <Sheet title="Server" onClose={() => setEditServer(false)}>
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); applyServer(); }}>
            <Notice tone="warn">Your sign-in is sent to this server. Only use one you run or fully trust.</Notice>
            {serverError && <Notice tone="error">{serverError}</Notice>}
            <input value={serverText} onChange={(e) => setServerText(e.target.value)} placeholder="https://api.example.com" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} aria-label="Server address" className="w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 font-mono text-[14px] text-ink outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
            <Button type="submit" className="w-full" disabled={!serverText.trim()}>Use this server</Button>
            {custom && <Button kind="quiet" className="w-full" onClick={() => { setEscanorApiBase(null); window.location.reload(); }}>Go back to Escanor’s server</Button>}
          </form>
        </Sheet>
      )}
      {confirmServer && <ConfirmSheet title="Change the server?" body={<>The app will connect to <b className="break-all font-mono text-ink">{confirmServer}</b> and you will be signed out of the current one. Make sure you trust it.</>} action="Change server" onClose={() => setConfirmServer(null)} onConfirm={() => { /* sign out of the OLD server first: the logout call carries the refresh token and must not reach the new one */ void escanor.signOut().finally(() => { setEscanorApiBase(confirmServer); window.location.reload(); }); }} />}
      {confirmReset && <ConfirmSheet title="Reset app data?" body="This phone forgets its preferences, the server override and every computer paired with it. Nothing changes on the computers themselves, and you can pair them again." action="Reset" onClose={() => setConfirmReset(false)} onConfirm={() => { resetPrefs(); clearComputers(); setEscanorApiBase(null); window.location.reload(); }} />}
    </Page>
  );
}
