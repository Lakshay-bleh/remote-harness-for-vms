import { CheckCircle, Warning, XCircle } from '@phosphor-icons/react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { DogRunner, DogState } from '../dog/DogState';
import { ago } from '../ui';
import { activityLabel } from './activityLabel';
import { mergeActivity, nextStep, oldest, PAGE } from './activityPaging';
import ErrorCard from './ErrorCard';
import type { ActivityItem, ClientMsg, ServerMsg } from './lib/protocol';
import { useRemote } from './useRemote';

type Request = (msg: ClientMsg) => Promise<ServerMsg[]>;
interface Page { items: ActivityItem[]; more: boolean | undefined }

async function fetchPage(request: Request, before?: string): Promise<Page> {
  const m = (await request({ t: 'activity', limit: PAGE, ...(before ? { before } : {}) })).find((x) => x.t === 'activity' || x.t === 'error');
  if (m?.t === 'activity') return { items: m.items, more: m.more };
  throw new Error(m?.t === 'error' ? m.message : 'The computer did not answer.');
}

/**
 * What phones and the voice assistant did on this computer lately, newest first. Loads a page at a time: the next page is fetched when
 * the end of the list scrolls into view, so opening this tab is quick however much has happened.
 */
export default function ActivityTab({ computerId, request, online }: { computerId: string; request: Request; online: boolean }) {
  const first = useRemote<Page>({ computerId, what: 'activity', online, run: useCallback(() => fetchPage(request), [request]), ttlMs: 10_000, everyMs: 20_000 });
  const [items, setItems] = useState<ActivityItem[]>(first.data?.items ?? []);
  const [serverMore, setServerMore] = useState<boolean | undefined>(first.data?.more);
  const [shown, setShown] = useState(PAGE);
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState<string | null>(null);
  const end = useRef<HTMLDivElement>(null);
  const olderLoaded = useRef(false); // once older pages are loaded, a refresh of the first page must not reset "more"

  useEffect(() => {
    if (!first.data) return;
    setItems((cur) => mergeActivity(cur, first.data!.items));
    if (!olderLoaded.current) setServerMore(first.data.more);
  }, [first.data]);

  const more = useCallback(async () => {
    const step = nextStep(items.length, shown, serverMore);
    if (step === 'reveal') return setShown((n) => n + PAGE);
    if (step === 'done' || loadingMore) return;
    setLoadingMore(true);
    setMoreError(null);
    try {
      const page = await fetchPage(request, oldest(items));
      olderLoaded.current = true;
      setItems((cur) => mergeActivity(cur, page.items));
      setServerMore(page.more);
      setShown((n) => n + PAGE);
    } catch (e) {
      setMoreError(e instanceof Error ? e.message : 'Could not load older activity.');
    } finally {
      setLoadingMore(false);
    }
  }, [items, shown, serverMore, loadingMore, request]);

  // The end of the list scrolling into view asks for the next page.
  const latest = useRef(more);
  latest.current = more;
  useEffect(() => {
    const el = end.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((e) => e[0]?.isIntersecting && void latest.current(), { rootMargin: '200px' });
    io.observe(el);
    return () => io.disconnect();
  }, [items.length, shown]);

  if (!first.data && items.length === 0) {
    if (first.error && !first.refreshing) return <div className="px-4 py-4"><ErrorCard error={first.error} onRetry={first.reload} /></div>;
    if (!online) return <DogState scene="sleep" title="Your computer is offline" text="Its activity will show here when it is back." />;
    return <DogState scene="dig" live title="Digging up what happened…" text="Asking your computer for its recent activity." />;
  }
  if (items.length === 0) return <DogState scene="dig" title="Nothing dug up yet" text="Things your phone and the assistant do on this computer show up here." />;

  const visible = items.slice(0, shown);
  const hasMore = shown < items.length || serverMore === true;
  return (
    <div className="px-4 pb-6">
      <ul className="divide-y divide-hairline">
        {visible.map((a, i) => {
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
      <div ref={end} aria-hidden className="h-px" />
      {loadingMore && <DogRunner label="Fetching older activity…" />}
      {moreError && <p className="py-3 text-center text-[13px] text-muted">{moreError} <button type="button" onClick={() => void more()} className="text-primary underline">Try again</button></p>}
      {!hasMore && items.length > PAGE && <p className="py-4 text-center text-[12px] text-muted-soft">That is everything.</p>}
    </div>
  );
}
