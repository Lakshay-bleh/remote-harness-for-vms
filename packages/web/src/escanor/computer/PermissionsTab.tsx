import { CheckCircle, LockSimple } from '@phosphor-icons/react';
import { useCallback, useEffect, useState } from 'react';
import { DogState } from '../dog/DogState';
import { Notice } from '../ui';
import { useRemote } from './useRemote';
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
export default function PermissionsTab({ computerId, request, online }: { computerId: string; request: Request; online: boolean }) {
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [watching, setWatching] = useState(false);

  const fetchGroups = useCallback(async (): Promise<PermissionGroup[]> => {
    const m = (await request({ t: 'groups' })).find((x) => x.t === 'groups' || x.t === 'error');
    if (m?.t === 'groups') return m.items;
    throw new Error(m?.t === 'error' ? m.message : 'The computer did not answer.');
  }, [request]);
  // What was shown last time appears at once; the list is checked again in the background (it rarely changes).
  const list = useRemote<PermissionGroup[]>({ computerId, what: 'groups', online, run: fetchGroups, ttlMs: 60_000 });
  const groups = list.data;
  const error = groups ? null : list.error;
  const load = list.reload;

  // After asking, look again every few seconds: the list changes the moment the person says yes on the computer.
  useEffect(() => {
    if (!watching || !online) return;
    const t = setInterval(() => list.reload(), 4000);
    const stop = setTimeout(() => setWatching(false), 120_000);
    return () => (clearInterval(t), clearTimeout(stop));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [watching, online]);

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

  if (!groups) {
    if (error && !list.refreshing) return <div className="px-4 py-4"><ErrorCard error={error} onRetry={() => void load()} /></div>;
    if (!online) return <DogState scene="sleep" title="Your computer is offline" text="Its permissions will show here when it is back." />;
    return <DogState scene="sniff" live title="Sniffing out the permissions…" text="Asking your computer what this phone may do." />;
  }

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
