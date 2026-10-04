import { ChatCircleText, ClockCounterClockwise, Gauge, LockKey, PencilSimple, PencilSimpleLine, ShieldCheck, Sliders, ArrowsClockwise, Trash } from '@phosphor-icons/react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useHardwareBack } from '../back';
import { dropCache } from '../cache';
import { forgetChats } from './chatStore';
import { OverflowMenu } from '../Menu';
import { ConfirmSheet } from '../settings/parts';
import { Notice, ScreenHeader } from '../ui';
import ActivityTab from './ActivityTab';
import ApprovalsTab, { type Approval } from './ApprovalsTab';
import ComputerChat, { type ChatActions } from './ComputerChat';
import ResourcesTab from './ResourcesTab';
import { applyRoute, displayName, forgetComputerPrefs, setComputerPrefs, useComputerPrefs } from './computerPrefs';
import ComputerSettings from './ComputerSettings';
import ErrorCard from './ErrorCard';
import type { PairedComputer } from './lib/client';
import PermissionsTab from './PermissionsTab';
import { describeGroupRequest, findGroup } from './permissions';
import RenameSheet from './RenameSheet';
import { useComputer } from './useComputer';

type Tab = 'chat' | 'resources' | 'approvals' | 'permissions' | 'activity';

const TABS: Array<{ id: Tab; label: string; Icon: typeof ChatCircleText }> = [
  { id: 'chat', label: 'Chat', Icon: ChatCircleText },
  { id: 'resources', label: 'Resources', Icon: Gauge },
  { id: 'approvals', label: 'Approvals', Icon: ShieldCheck },
  { id: 'permissions', label: 'Permissions', Icon: LockKey },
  { id: 'activity', label: 'Activity', Icon: ClockCounterClockwise },
];

/** The strip of sections: icons with names, a badge where something waits, scrolls sideways if the phone is narrow. */
function TabStrip({ tab, onPick, badges, chat }: { tab: Tab; onPick: (t: Tab) => void; badges: Partial<Record<Tab, number>>; chat: ChatActions | null }) {
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
      {/* The chat's own buttons sit in this bar, after the sections, so no row of their own takes space from the conversation. */}
      {chat && tab === 'chat' && (
        <span className="sticky right-0 ml-auto flex shrink-0 items-center gap-0.5 bg-canvas pl-2">
          <button type="button" onClick={chat.history} aria-label="Chat history" className="flex h-9 w-9 items-center justify-center rounded-full text-body transition hover:bg-surface-card active:scale-90"><ClockCounterClockwise size={20} /></button>
          <button type="button" onClick={chat.newChat} aria-label="New chat" disabled={!chat.canNew} className="flex h-9 w-9 items-center justify-center rounded-full text-body transition hover:bg-surface-card active:scale-90 disabled:opacity-40"><PencilSimpleLine size={20} /></button>
        </span>
      )}
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
  const [chatActions, setChatActions] = useState<ChatActions | null>(null);
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

  const remove = () => (forgetComputerPrefs(computer.id), forgetChats(computer.id), dropCache(`computer:${computer.id}:`), onRemove());

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

      <TabStrip tab={tab} onPick={setTab} badges={{ approvals: approvals.length }} chat={chatActions} />

      {link.state === 'offline' && <div className="px-4 pt-3"><ErrorCard error={link.error ?? 'This computer is not reachable.'} onRetry={() => void link.reconnect()} /></div>}
      {approvals.length > 0 && tab !== 'approvals' && (
        <div className="px-4 pt-3"><button onClick={() => setTab('approvals')} className="w-full text-left"><Notice tone="warn">{approvals[0].describe}: waiting for your OK.</Notice></button></div>
      )}

      <div className="min-h-0 flex-1">
        {/* The chat stays mounted while another section is open, so what you were typing and the reply on its way are not lost. */}
        <div className={tab === 'chat' ? 'h-full' : 'hidden'}><ComputerChat computerId={computer.id} request={link.request} online={online} onAsk={askToAllow} onActions={setChatActions} /></div>
        {tab === 'resources' && <div className="h-full overflow-y-auto"><ResourcesTab computerId={computer.id} request={link.request} online={online} route={link.route} /></div>}
        {tab === 'approvals' && <div className="h-full overflow-y-auto"><ApprovalsTab items={approvals} onAnswer={answer} online={online} /></div>}
        {tab === 'permissions' && <div className="h-full overflow-y-auto"><PermissionsTab computerId={computer.id} request={link.request} online={online} /></div>}
        {tab === 'activity' && <div className="h-full overflow-y-auto"><ActivityTab computerId={computer.id} request={link.request} online={online} /></div>}
      </div>

      {sheet === 'rename' && <RenameSheet current={prefs.alias} original={computer.name} onSave={(alias) => setComputerPrefs(computer.id, { alias })} onClose={() => setSheet(null)} />}
      {sheet === 'remove' && <ConfirmSheet title={`Forget ${name}?`} body="This phone will no longer control it. You can pair it again any time with a new code." action="Forget" onConfirm={remove} onClose={() => setSheet(null)} />}
    </div>
  );
}
