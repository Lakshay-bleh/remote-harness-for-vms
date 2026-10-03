import { CheckCircle, LockSimple } from '@phosphor-icons/react';
import { useCallback, useEffect, useState } from 'react';
import { Notice, Spinner } from '../ui';
import ErrorCard from './ErrorCard';
import type { PermissionGroup } from './lib/protocol';
import type { ServerMsg, ClientMsg } from './lib/protocol';
import { describeGroupRequest, sortGroups } from './permissions';
import { Button } from '../ui';

type Request = (msg: ClientMsg) => Promise<ServerMsg[]>;

/**
 * What this phone may do on the computer. Switched-off kinds can be requested from here, but only the person at the computer can
 * allow them: the computer shows a question, and the phone has no way to answer it.
 */
export default function PermissionsTab({ request, online }: { request: Request; online: boolean }) {
  const [groups, setGroups] = useState<PermissionGroup[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [watching, setWatching] = useState(false);

  const load = useCallback(async () => {
    try {
      const m = (await request({ t: 'groups' })).find((x) => x.t === 'groups' || x.t === 'error');
      if (m?.t === 'groups') (setGroups(m.items), setError(null));
      else if (m?.t === 'error') setError(m.message);
    } catch (e) {
      setError(e);
    }
  }, [request]);

  useEffect(() => { if (online) void load(); }, [online, load]);
  // After asking, look again every few seconds: the list changes the moment the person says yes on the computer.
  useEffect(() => {
    if (!watching || !online) return;
    const t = setInterval(() => void load(), 4000);
    const stop = setTimeout(() => setWatching(false), 120_000);
    return () => (clearInterval(t), clearTimeout(stop));
  }, [watching, online, load]);

  const ask = async (g: PermissionGroup) => {
    setBusy(g.id);
    try {
      const m = (await request({ t: 'request_group', group: g.id })).find((x) => x.t === 'group_request' || x.t === 'error');
      setNotes((n) => ({ ...n, [g.id]: m?.t === 'group_request' ? describeGroupRequest(m.status, g.label) : m?.t === 'error' ? m.message : 'No answer.' }));
      if (m?.t === 'group_request' && m.status === 'asked') setWatching(true);
    } catch (e) {
      setNotes((n) => ({ ...n, [g.id]: e instanceof Error ? e.message : 'That did not work.' }));
    } finally {
      setBusy(null);
    }
  };

  if (error) return <div className="px-4 py-4"><ErrorCard error={error} onRetry={() => void load()} /></div>;
  if (!groups) return <div className="flex items-center gap-2 px-4 py-8 text-sm text-muted">{online ? <><Spinner /> Asking your computer…</> : 'Computer offline'}</div>;

  const off = groups.filter((g) => !g.enabled).length;
  return (
    <div className="space-y-4 px-4 pb-6 pt-3">
      <p className="text-[13px] leading-relaxed text-muted">What this phone is allowed to do on your computer. {off ? `${off} kind${off === 1 ? ' is' : 's are'} switched off. Ask to switch one on and approve it on the computer.` : 'Everything is allowed.'} Change these any time on the computer in Escanor Desktop → Settings → Permissions.</p>
      <ul className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
        {sortGroups(groups).map((g) => (
          <li key={g.id} className="px-3.5 py-3">
            <div className="flex items-start gap-3">
              <span className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${g.enabled ? 'bg-success/10 text-success' : 'bg-canvas text-muted'}`}>{g.enabled ? <CheckCircle size={18} weight="fill" /> : <LockSimple size={18} />}</span>
              <span className="min-w-0 flex-1">
                <span className="block text-[15px] text-ink">{g.label}</span>
                <span className="block text-[12px] leading-snug text-muted">{g.about}</span>
              </span>
              {g.enabled ? <span className="shrink-0 text-[12px] text-success">Allowed</span> : <Button kind="quiet" className="!px-3 !py-1.5 text-[13px]" onClick={() => void ask(g)} disabled={busy === g.id || !online}>{busy === g.id ? 'Asking…' : 'Ask to allow'}</Button>}
            </div>
            {notes[g.id] && !g.enabled && <div className="mt-2"><Notice>{notes[g.id]}</Notice></div>}
          </li>
        ))}
      </ul>
    </div>
  );
}
