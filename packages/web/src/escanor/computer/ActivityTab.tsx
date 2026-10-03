import { CheckCircle, Warning, XCircle } from '@phosphor-icons/react';
import { useCallback, useEffect, useState } from 'react';
import { ago, Spinner } from '../ui';
import { activityLabel } from './activityLabel';
import ErrorCard from './ErrorCard';
import type { ActivityItem, ClientMsg, ServerMsg } from './lib/protocol';

type Request = (msg: ClientMsg) => Promise<ServerMsg[]>;

/** What phones and the voice assistant did on this computer lately, newest first. */
export default function ActivityTab({ request, online }: { request: Request; online: boolean }) {
  const [items, setItems] = useState<ActivityItem[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    try {
      const m = (await request({ t: 'activity' })).find((x) => x.t === 'activity' || x.t === 'error');
      if (m?.t === 'activity') (setItems(m.items), setError(null));
      else if (m?.t === 'error') setError(m.message);
    } catch (e) {
      setError(e);
    }
  }, [request]);

  useEffect(() => {
    if (!online) return;
    void load();
    const t = setInterval(() => void load(), 10_000);
    return () => clearInterval(t);
  }, [online, load]);

  if (error) return <div className="px-4 py-4"><ErrorCard error={error} onRetry={() => void load()} /></div>;
  if (!items) return <div className="flex items-center gap-2 px-4 py-8 text-sm text-muted">{online ? <><Spinner /> Asking your computer…</> : 'Computer offline'}</div>;
  if (items.length === 0) return <p className="px-4 py-10 text-center text-sm text-muted">Nothing has happened yet. Things your phone and the assistant do on this computer show up here.</p>;

  return (
    <ul className="divide-y divide-hairline px-4 pb-6">
      {items.map((a, i) => {
        const ok = a.outcome === 'ok';
        const refused = a.outcome === 'forbidden' || a.outcome === 'denied';
        const Icon = ok ? CheckCircle : refused ? Warning : XCircle;
        return (
          <li key={`${a.at}-${i}`} className="flex items-start gap-3 py-3">
            <Icon size={20} weight="fill" className={`mt-0.5 shrink-0 ${ok ? 'text-success' : refused ? 'text-warning' : 'text-error'}`} aria-hidden />
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[14px] text-ink">{activityLabel(a.capabilityId)}</span>
              <span className="block truncate text-[12px] text-muted">{a.caller.replace(/^phone:/, 'From ').replace(/^voice$/, 'Voice assistant')} · {ago(a.at)}{ok ? '' : refused ? ' · was not allowed' : ' · did not work'}</span>
              {a.message && !ok && <span className="mt-0.5 line-clamp-2 block text-[12px] leading-snug text-body">{a.message}</span>}
            </span>
            {a.risk !== 'read' && <span className={`shrink-0 rounded-pill px-2 py-0.5 text-[11px] ${a.risk === 'destructive' ? 'bg-error/10 text-error' : 'bg-surface-cream-strong text-muted'}`}>{a.risk === 'destructive' ? 'Deletes' : 'Changes'}</span>}
          </li>
        );
      })}
    </ul>
  );
}
