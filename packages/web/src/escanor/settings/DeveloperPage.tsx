import { ArrowsClockwise, Bug, Copy, Globe, Key, Plugs, Trash } from '@phosphor-icons/react';
import { useState } from 'react';
import { isNative } from '../../api';
import { APP_VERSION } from '../../appInfo';
import { escanor, type McpConnection, type McpInstall } from '../client';
import { clearComputers, loadComputers } from '../computer/storage';
import { escanorApiBase } from '../config';
import { useLoad } from '../hooks';
import { useEscanorSession } from '../session';
import { ago, Button, Notice, Sheet, Spinner } from '../ui';
import { ConfirmSheet, Group, Page, Row } from './parts';
import { resetChatMeta } from '../chatList';
import { resetPrefs } from './prefs';

const host = (url: string) => { try { return new URL(url).host; } catch { return url; } };

type Check = { state: 'idle' } | { state: 'running' } | { state: 'done'; ok: boolean; ms: number; status: number };

/** For people who build on Escanor: where the app connects, whether it can reach it, keys for other AI apps, and what to send when asking for help. */
export default function DeveloperPage({ onBack, onHelp }: { onBack: () => void; onHelp: () => void }) {
  const { user } = useEscanorSession();
  const mcp = useLoad(() => escanor.mcpConnections(), 0);
  const apps = (mcp.data ?? []).filter((c) => !c.revoked_at && !c.managed_by);
  const [check, setCheck] = useState<Check>({ state: 'idle' });
  const [install, setInstall] = useState<McpInstall | null>(null);
  const [creating, setCreating] = useState(false);
  const [keyError, setKeyError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [confirmReset, setConfirmReset] = useState(false);
  const [editKey, setEditKey] = useState<McpConnection | null>(null);
  const api = escanorApiBase();

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
      `Server: ${api}`,
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

  return (
    <Page title="Developer" subtitle="For building on Escanor and asking for help" onBack={onBack}>
      <Group title="Connection" footer="The app always talks to Escanor’s own server. Test checks that it answers; it does not need you to be signed in.">
        <Row icon={<Globe size={18} />} label="Server" value={host(api)} />
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
        <p className="mb-2 px-1 text-[12px] leading-relaxed text-muted">Give Claude, Cursor or another AI app access to your connected services. Each gets its own key. Tap a key to rename it, replace it or delete it.</p>
        {keyError && <div className="mb-2"><Notice tone="error">{keyError}</Notice></div>}
        <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
          {mcp.loading && !mcp.data ? <div className="p-4 text-center"><Spinner /></div> : apps.length === 0 ? (
            <p className="px-3.5 py-3 text-sm text-muted">No keys yet.</p>
          ) : (
            apps.map((c) => <Row key={c.id} icon={<Key size={18} />} label={c.name} sub={`${c.token_prefix ? `${c.token_prefix}… · ` : ''}${c.total_calls.toLocaleString()} calls`} value={c.last_used_at ? `used ${ago(c.last_used_at)}` : 'not used yet'} onClick={() => setEditKey(c)} />)
          )}
          <Row icon={<Key size={18} />} label={creating ? 'Creating…' : 'Create a key'} onClick={() => void createKey()} disabled={creating} />
        </div>
      </section>

      <Group title="Help and diagnostics" footer="The debug details contain no passwords or tokens.">
        <Row icon={<Copy size={18} />} label="Copy debug info" value={copied === 'debug' ? 'Copied' : undefined} onClick={() => void copy('debug', debugInfo())} chevron={false} />
        <Row icon={<Bug size={18} />} label="Report a problem" onClick={onHelp} />
        <Row icon={<ArrowsClockwise size={18} />} label="Reload the app" onClick={() => window.location.reload()} chevron={false} />
      </Group>

      <Group title="This phone" footer="Removes saved preferences, pinned and renamed chats and the computers paired with this phone. You stay signed in.">
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

      {editKey && <KeySheet connection={editKey} onClose={() => setEditKey(null)} onChanged={() => mcp.reload()} onNewKey={(k) => setInstall(k)} />}

      {confirmReset && <ConfirmSheet title="Reset app data?" body="This phone forgets its preferences, pinned and renamed chats, and every computer paired with it. Nothing changes on the computers themselves, and you can pair them again." action="Reset" onClose={() => setConfirmReset(false)} onConfirm={() => { resetPrefs(); resetChatMeta(); clearComputers(); window.location.reload(); }} />}
    </Page>
  );
}

/** One key for another AI app: rename it, replace it with a fresh one (the old stops working), or delete it. */
function KeySheet({ connection, onClose, onChanged, onNewKey }: { connection: McpConnection; onClose: () => void; onChanged: () => void; onNewKey: (k: McpInstall) => void }) {
  const [name, setName] = useState(connection.name);
  const [busy, setBusy] = useState<null | 'save' | 'rotate' | 'delete'>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<null | 'rotate' | 'delete'>(null);
  const clean = name.replace(/\s+/g, ' ').trim();

  const run = async (what: 'save' | 'rotate' | 'delete', job: () => Promise<void>) => {
    setBusy(what);
    setError(null);
    setConfirm(null);
    try {
      await job();
      onChanged();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That did not work. Try again.');
      setBusy(null);
    }
  };

  return (
    <>
      <Sheet title="Key" onClose={onClose}>
        <div className="space-y-4">
          {error && <Notice tone="error">{error}</Notice>}
          <form className="space-y-2" onSubmit={(e) => { e.preventDefault(); if (clean && clean !== connection.name) void run('save', async () => { await escanor.renameMcp(connection.id, clean); onClose(); }); }}>
            <label className="block text-sm text-body">Name
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} aria-label="Key name" className="mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-[15px] text-ink outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
            </label>
            <Button type="submit" className="w-full" disabled={!clean || clean === connection.name || busy !== null}>{busy === 'save' ? 'Saving…' : 'Save name'}</Button>
          </form>
          <p className="text-[12px] text-muted">{connection.token_prefix ? <>Starts with <span className="font-mono">{connection.token_prefix}…</span> · </> : null}created {ago(connection.created_at)}{connection.last_used_at ? `, last used ${ago(connection.last_used_at)}` : ', not used yet'}. The key itself is never shown again.</p>
          <div className="space-y-2 border-t border-hairline pt-3">
            <Button kind="quiet" className="w-full" disabled={busy !== null} onClick={() => setConfirm('rotate')}>Replace with a new key</Button>
            <Button kind="danger" className="w-full" disabled={busy !== null} onClick={() => setConfirm('delete')}>Delete this key</Button>
          </div>
        </div>
      </Sheet>
      {confirm === 'rotate' && <ConfirmSheet title="Replace this key?" body="You get a new key to copy now. The old one stops working immediately, so any app using it needs the new one." action="Replace" busy={busy === 'rotate'} onClose={() => setConfirm(null)} onConfirm={() => void run('rotate', async () => { const fresh = await escanor.rotateMcp(connection.id); onClose(); onNewKey(fresh); })} />}
      {confirm === 'delete' && <ConfirmSheet title="Delete this key?" body={<>Apps using <b className="text-ink">{connection.name}</b> lose access to your connected services straight away. This cannot be undone, but you can always create a new key.</>} action="Delete" busy={busy === 'delete'} onClose={() => setConfirm(null)} onConfirm={() => void run('delete', async () => { await escanor.revokeMcp(connection.id); onClose(); })} />}
    </>
  );
}
