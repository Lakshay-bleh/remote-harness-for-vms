import { ChatCircleText, ClockCounterClockwise, Gauge, LockKey, PencilSimple, ShieldCheck, Sliders, ArrowsClockwise, Trash } from '@phosphor-icons/react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useHardwareBack } from '../back';
import { OverflowMenu } from '../Menu';
import { ConfirmSheet } from '../settings/parts';
import { Button, Notice, ScreenHeader, Spinner } from '../ui';
import ActivityTab from './ActivityTab';
import { applyRoute, displayName, forgetComputerPrefs, setComputerPrefs, useComputerPrefs } from './computerPrefs';
import ComputerSettings from './ComputerSettings';
import ErrorCard from './ErrorCard';
import { explainFailure } from './errors';
import type { PairedComputer } from './lib/client';
import type { ServerMsg } from './lib/protocol';
import PermissionsTab from './PermissionsTab';
import { describeGroupRequest, findGroup } from './permissions';
import RenameSheet from './RenameSheet';
import { useComputer } from './useComputer';

type Tab = 'chat' | 'resources' | 'approvals' | 'permissions' | 'activity';
interface Turn { who: 'you' | 'computer'; text: string; /** The computer's reply was a refusal: shown as an explained error, not a bubble. */ problem?: boolean }
type Approval = Extract<ServerMsg, { t: 'approval' }>;

const gb = (n: number) => `${(n / 1024 ** 3).toFixed(1)} GB`;
const uid = () => Math.random().toString(36).slice(2, 10);

function Meter({ value }: { value: number }) {
  const v = Math.min(100, Math.max(0, value));
  return <div className="h-2 overflow-hidden rounded-full bg-surface-card"><div className={`h-full rounded-full ${v > 90 ? 'bg-error' : v > 75 ? 'bg-permission' : 'bg-primary'}`} style={{ width: `${v}%` }} /></div>;
}

const TABS: Array<{ id: Tab; label: string; Icon: typeof ChatCircleText }> = [
  { id: 'chat', label: 'Chat', Icon: ChatCircleText },
  { id: 'resources', label: 'Resources', Icon: Gauge },
  { id: 'approvals', label: 'Approvals', Icon: ShieldCheck },
  { id: 'permissions', label: 'Permissions', Icon: LockKey },
  { id: 'activity', label: 'Activity', Icon: ClockCounterClockwise },
];

/** The strip of sections: icons with names, a badge where something waits, scrolls sideways if the phone is narrow. */
function TabStrip({ tab, onPick, badges }: { tab: Tab; onPick: (t: Tab) => void; badges: Partial<Record<Tab, number>> }) {
  return (
    <div role="tablist" aria-label="Sections" className="flex shrink-0 gap-0.5 overflow-x-auto border-b border-hairline px-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {TABS.map(({ id, label, Icon }) => {
        const active = tab === id;
        const n = badges[id];
        return (
          <button key={id} role="tab" aria-selected={active} onClick={() => onPick(id)} className={`relative flex shrink-0 items-center gap-1.5 px-3.5 py-3 text-[14px] outline-none transition active:scale-95 ${active ? 'font-medium text-ink' : 'text-muted hover:text-body'}`}>
            <Icon size={18} weight={active ? 'fill' : 'regular'} aria-hidden className={active ? 'text-primary' : ''} />
            {label}
            {n ? <span className="rounded-pill bg-primary px-1.5 text-[11px] font-semibold leading-[18px] text-on-primary">{n}</span> : null}
            {active && <span aria-hidden className="absolute inset-x-3 bottom-0 h-0.5 rounded-full bg-primary" />}
          </button>
        );
      })}
    </div>
  );
}

export default function ComputerDetail({ computer, onBack, onRemove }: { computer: PairedComputer; onBack: () => void; onRemove: () => void }) {
  const prefs = useComputerPrefs(computer.id);
  // The person's "how to reach it" choice, applied to this connection only. Memoised: a new object every render would reconnect every render.
  const routed = useMemo(() => applyRoute(computer, prefs.route), [computer, prefs.route]);
  const link = useComputer(routed.computer, routed.cloud);
  const { request } = link;
  const name = displayName(computer, prefs);
  const [view, setView] = useState<'main' | 'settings'>('main');
  const [tab, setTab] = useState<Tab>('chat');
  const [approvals, setApprovals] = useState<Approval[]>([]);
  const [sheet, setSheet] = useState<'rename' | 'remove' | null>(null);
  useHardwareBack(view === 'main', onBack);

  // Approvals arrive by push on the local network, and are fetched on a timer over the cloud.
  useEffect(
    () =>
      link.onPush((m) => {
        if (m.t === 'approval') setApprovals((a) => (a.some((x) => x.approvalId === m.approvalId) ? a : [...a, m]));
        if (m.t === 'approval_done') setApprovals((a) => a.filter((x) => x.approvalId !== m.approvalId));
      }),
    [link],
  );
  useEffect(() => {
    // Keep asking while connecting or online. (Once it is offline the link retries by itself, so this stays quiet.)
    if (link.state === 'offline') return;
    let stop = false;
    let inFlight = false; // over the cloud one answer can take a few seconds: never queue another behind it
    const poll = async () => {
      if (inFlight) return;
      inFlight = true;
      try {
        const r = (await request({ t: 'pending' })).find((m) => m.t === 'pending');
        if (!stop && r && r.t === 'pending') setApprovals(r.approvals.map((a) => ({ t: 'approval' as const, ...a })));
      } catch {
        // the banner says so once it counts as offline
      } finally {
        inFlight = false;
      }
    };
    if (link.state === 'online') void poll();
    const t = setInterval(poll, link.route === 'lan' ? 15000 : 8000);
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, [link.state, link.route, request]);

  const answer = async (a: Approval, ok: boolean) => {
    setApprovals((x) => x.filter((y) => y.approvalId !== a.approvalId));
    await link.request({ t: 'approve', approvalId: a.approvalId, ok }).catch(() => undefined);
  };

  /** Ask the computer to switch on a kind of action that was refused, from the error card. Resolves with what to tell the person. */
  const askToAllow = useCallback(
    async (groupLabel: string): Promise<string> => {
      const list = (await request({ t: 'groups' })).find((m) => m.t === 'groups');
      const g = list?.t === 'groups' ? findGroup(list.items, groupLabel) : undefined;
      if (!g) return describeGroupRequest('unknown', groupLabel);
      const r = (await request({ t: 'request_group', group: g.id })).find((m) => m.t === 'group_request');
      return r?.t === 'group_request' ? describeGroupRequest(r.status, g.label) : describeGroupRequest('unknown', g.label);
    },
    [request],
  );

  const testConnection = useCallback(async () => {
    const t = performance.now();
    await request({ t: 'ping' });
    return Math.round(performance.now() - t);
  }, [request]);

  const remove = () => (forgetComputerPrefs(computer.id), onRemove());

  if (view === 'settings') {
    return <ComputerSettings computer={computer} prefs={prefs} state={link.state} route={link.route} onBack={() => setView('main')} onReconnect={() => void link.reconnect()} onTest={testConnection} onRemove={remove} />;
  }

  const subtitle = link.state === 'connecting' ? 'Connecting…' : link.state === 'offline' ? 'Offline' : link.route === 'lan' ? 'Connected over Wi-Fi' : 'Connected through the cloud';
  const online = link.state === 'online';

  return (
    <div className="flex h-full min-h-0 flex-col">
      <ScreenHeader title={name} onBack={onBack} subtitle={subtitle}>
        <span className={`h-2.5 w-2.5 rounded-full ${online ? 'bg-success' : link.state === 'connecting' ? 'bg-warning' : 'bg-line-strong'}`} aria-hidden />
        <OverflowMenu
          label={`Options for ${name}`}
          items={[
            { label: 'Rename', icon: <PencilSimple size={18} />, onClick: () => setSheet('rename') },
            { label: 'Computer settings', icon: <Sliders size={18} />, onClick: () => setView('settings') },
            { label: 'Reconnect', icon: <ArrowsClockwise size={18} />, onClick: () => void link.reconnect() },
            { label: 'Forget this computer', icon: <Trash size={18} />, danger: true, divider: true, onClick: () => setSheet('remove') },
          ]}
        />
      </ScreenHeader>

      <TabStrip tab={tab} onPick={setTab} badges={{ approvals: approvals.length }} />

      {link.state === 'offline' && <div className="px-4 pt-3"><ErrorCard error={link.error ?? 'This computer is not reachable.'} onRetry={() => void link.reconnect()} /></div>}
      {approvals.length > 0 && tab !== 'approvals' && (
        <div className="px-4 pt-3"><button onClick={() => setTab('approvals')} className="w-full text-left"><Notice tone="warn">{approvals[0].describe}: waiting for your OK.</Notice></button></div>
      )}

      <div className="min-h-0 flex-1 overflow-y-auto">
        {tab === 'chat' && <Chat request={link.request} online={online} onAsk={askToAllow} />}
        {tab === 'resources' && <Resources request={link.request} online={online} />}
        {tab === 'approvals' && <Approvals items={approvals} onAnswer={answer} />}
        {tab === 'permissions' && <PermissionsTab request={link.request} online={online} />}
        {tab === 'activity' && <ActivityTab request={link.request} online={online} />}
      </div>

      {sheet === 'rename' && <RenameSheet current={prefs.alias} original={computer.name} onSave={(alias) => setComputerPrefs(computer.id, { alias })} onClose={() => setSheet(null)} />}
      {sheet === 'remove' && <ConfirmSheet title={`Forget ${name}?`} body="This phone will no longer control it. You can pair it again any time with a new code." action="Forget" onConfirm={remove} onClose={() => setSheet(null)} />}
    </div>
  );
}

function Chat({ request, online, onAsk }: { request: ReturnType<typeof useComputer>['request']; online: boolean; onAsk: (groupLabel: string) => Promise<string> }) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  // Braces matter: an effect's return value is its cleanup, and scrollIntoView() may return a Promise.
  useEffect(() => {
    end.current?.scrollIntoView({ block: 'end' });
  }, [turns, busy]);

  const send = useCallback(
    async (raw: string) => {
      const line = raw.trim();
      if (!line || busy) return;
      setText('');
      setTurns((t) => [...t, { who: 'you', text: line }]);
      setBusy(true);
      try {
        const id = uid();
        const out = await request({ t: 'chat', id, text: line });
        const reply = out.find((m) => m.t === 'reply' || m.t === 'error');
        const said = reply ? (reply.t === 'reply' ? reply.reply : reply.message) : 'Done.';
        // A reply that is really "that is switched off" (or any other error in words) is shown as an explained error with its fix.
        setTurns((t) => [...t, { who: 'computer', text: said, problem: reply?.t === 'error' || explainFailure(said).ask !== undefined }]);
      } catch (e) {
        setTurns((t) => [...t, { who: 'computer', text: e instanceof Error ? e.message : 'That did not work.', problem: true }]);
      } finally {
        setBusy(false);
      }
    },
    [busy, request],
  );

  const suggestions = ['What is using my memory?', 'Show my containers', 'Volume up', 'Open YouTube'];
  return (
    <div className="flex h-full flex-col px-4">
      <div className="flex-1 space-y-3 py-2">
        {turns.length === 0 && (
          <div className="space-y-3 py-6 text-center">
            <p className="text-sm text-body">Ask your computer to do anything. It runs on its own hardware; you just see the result.</p>
            <div className="flex flex-wrap justify-center gap-2">{suggestions.map((s) => <button key={s} onClick={() => void send(s)} disabled={!online} className="rounded-pill border border-hairline px-3.5 py-1.5 text-sm text-body transition hover:bg-surface-card disabled:opacity-50">{s}</button>)}</div>
          </div>
        )}
        {turns.map((t, i) => t.problem ? <div key={i} className="max-w-[94%]"><ErrorCard error={t.text} onAsk={onAsk} /></div> : <div key={i} className={`flex ${t.who === 'you' ? 'justify-end' : ''}`}><p className={`max-w-[88%] whitespace-pre-wrap rounded-lg px-4 py-2.5 text-[15px] leading-relaxed ${t.who === 'you' ? 'bg-primary text-on-primary' : 'border border-hairline bg-surface-card text-ink'}`}>{t.text}</p></div>)}
        {busy && <div className="flex items-center gap-2 text-sm text-muted"><Spinner /> Working on your computer…</div>}
        <div ref={end} />
      </div>
      <form className="sticky bottom-0 flex gap-2 bg-canvas py-3" onSubmit={(e) => { e.preventDefault(); void send(text); }}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={online ? 'Tell your computer what to do…' : 'Computer offline'} disabled={!online} className="min-w-0 flex-1 rounded-pill border border-hairline bg-surface-card px-4 py-3 text-[15px] text-ink outline-none focus:border-primary disabled:opacity-60" />
        <Button type="submit" disabled={!online || busy || !text.trim()}>Send</Button>
      </form>
    </div>
  );
}

interface Stats { cpu: { load: number; model: string; cores: number }; mem: { used: number; total: number }; disks: Array<{ mount: string; used: number; size: number; usePercent: number }>; os: { hostname: string; uptimeSec: number }; battery: { percent: number; charging: boolean } | null; tempC: number | null }

function Resources({ request, online }: { request: ReturnType<typeof useComputer>['request']; online: boolean }) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [procs, setProcs] = useState<Array<{ pid: number; name: string; cpu: number; memBytes: number }>>([]);
  useEffect(() => {
    if (!online) return;
    let stop = false;
    const load = async () => {
      try {
        const [s, p] = await Promise.all([request({ t: 'call', id: uid(), capability: 'system.stats' }), request({ t: 'call', id: uid(), capability: 'system.processes', input: { limit: 6 } })]);
        const sr = s.find((m) => m.t === 'result');
        const pr = p.find((m) => m.t === 'result');
        if (!stop && sr?.t === 'result' && sr.ok) setStats(sr.result as Stats);
        if (!stop && pr?.t === 'result' && pr.ok) setProcs(pr.result as typeof procs);
      } catch {
        // the banner says when the computer is unreachable
      }
    };
    void load();
    const t = setInterval(load, 4000);
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, [online, request]);

  if (!stats) return <div className="flex items-center gap-2 px-4 py-8 text-sm text-muted">{online ? <><Spinner /> Reading your computer…</> : 'Computer offline'}</div>;
  const memPct = (stats.mem.used / stats.mem.total) * 100;
  return (
    <div className="space-y-4 px-4 pb-4">
      <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">CPU</span><span className="font-medium text-ink">{stats.cpu.load.toFixed(0)}%</span></div><div className="mt-2"><Meter value={stats.cpu.load} /></div><p className="mt-2 truncate text-[12px] text-muted">{stats.cpu.model} · {stats.cpu.cores} threads{stats.tempC ? ` · ${stats.tempC.toFixed(0)}°C` : ''}</p></div>
      <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">Memory</span><span className="font-medium text-ink">{gb(stats.mem.used)} of {gb(stats.mem.total)}</span></div><div className="mt-2"><Meter value={memPct} /></div></div>
      {stats.disks[0] && <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">Storage</span><span className="font-medium text-ink">{gb(stats.disks[0].used)} of {gb(stats.disks[0].size)}</span></div><div className="mt-2"><Meter value={stats.disks[0].usePercent} /></div></div>}
      {stats.battery && <p className="text-sm text-body">Battery {Math.round(stats.battery.percent)}%{stats.battery.charging ? ', charging' : ''}</p>}
      {procs.length > 0 && (
        <div className="rounded-lg border border-hairline bg-surface-card"><p className="px-4 pt-3 text-[12px] font-medium uppercase tracking-wide text-muted">Busiest programs</p><ul className="divide-y divide-hairline">{procs.map((p) => <li key={p.pid} className="flex justify-between gap-3 px-4 py-2.5 text-sm"><span className="truncate text-ink">{p.name}</span><span className="shrink-0 text-muted">{p.cpu.toFixed(1)}% · {(p.memBytes / 1024 ** 2).toFixed(0)} MB</span></li>)}</ul></div>
      )}
    </div>
  );
}

function Approvals({ items, onAnswer }: { items: Approval[]; onAnswer: (a: Approval, ok: boolean) => void }) {
  if (items.length === 0) return <p className="px-4 py-10 text-center text-sm text-muted">Nothing is waiting for your OK.</p>;
  return (
    <div className="space-y-3 px-4 pb-4">
      {items.map((a) => (
        <div key={a.approvalId} className={`rounded-lg border p-4 ${a.risk === 'destructive' ? 'border-error/40 bg-error/5' : 'border-permission/30 bg-permission/5'}`}>
          <p className="text-[13px] font-medium uppercase tracking-wide text-muted">{a.risk === 'destructive' ? 'Needs your care' : 'Needs your OK'}</p>
          <p className="mt-1 text-[15px] font-medium text-ink">{a.describe}</p>
          <pre className="mt-2 max-h-32 overflow-auto whitespace-pre-wrap break-words rounded-md bg-surface-dark p-3 font-mono text-[12px] text-on-dark">{JSON.stringify(a.input, null, 2)}</pre>
          <div className="mt-3 flex gap-2"><Button onClick={() => onAnswer(a, true)}>Continue</Button><Button kind="quiet" onClick={() => onAnswer(a, false)}>Don’t do this</Button></div>
        </div>
      ))}
    </div>
  );
}
