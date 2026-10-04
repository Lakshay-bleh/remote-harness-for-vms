import { useContext, useEffect, useMemo, useState } from 'react';
import type { ClaudeAccount, SessionDto } from '@remote-harness/shared';
import { useStore } from '../store';
import EscanorConnect from './EscanorConnect';
import { ConnectMachineSheet } from '../escanor/ConnectMachine';
import { useManagedHub } from '../escanor/ManagedMachines';
import { Desktop, Plus } from '@phosphor-icons/react';
import { DogState } from '../escanor/dog/DogState';
import { Button, EmbeddedContext, Logo, ScreenHeader } from '../escanor/ui';

const SESSIONS_FIRST = 8;

/** "Online", or when it was last seen: the same plain status a computer card gives. */
function machineStatus(vm: { connected: boolean; lastSeenAt: string | null }): string {
  if (vm.connected) return 'Online';
  return vm.lastSeenAt ? `Offline · seen ${relativeTime(vm.lastSeenAt)} ago` : 'Offline';
}

function relativeTime(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

const PersonIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <circle cx="12" cy="8" r="4" stroke="currentColor" strokeWidth="2" />
    <path d="M4 20c0-4 3.5-6 8-6s8 2 8 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
  </svg>
);

function SessionRow({ s, active, onClick }: { s: SessionDto; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full flex-col gap-0.5 rounded-md px-2.5 py-2 text-left transition hover:bg-surface-card ${active ? 'bg-surface-card' : ''}`}
    >
      <span className={`flex items-center gap-1.5 truncate text-[13px] ${active ? 'font-medium text-ink' : 'text-body'}`}>
        {s.status === 'active' && <span className="h-1.5 w-1.5 shrink-0 animate-pulseDot rounded-full bg-primary" />}
        <span className="truncate">{s.title}</span>
      </span>
      <span className="truncate text-[11px] text-muted-soft">{relativeTime(s.lastMessageAt)} ago · {s.cwd}</span>
    </button>
  );
}

function NewChatRow({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="mb-0.5 flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] text-primary transition hover:bg-primary/10">
      <span className="text-base leading-none">+</span> New chat
    </button>
  );
}

export default function Sidebar({ className, onSelectSession }: { className: string; onSelectSession: () => void }) {
  const { state, actions } = useStore();
  const [expandedVmId, setExpandedVmId] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const managed = useManagedHub();
  const embedded = useContext(EmbeddedContext);
  const [connecting, setConnecting] = useState(false);
  const [more, setMore] = useState<Record<string, number>>({});

  useEffect(() => {
    actions.refreshVms();
  }, []);

  useEffect(() => {
    if (!expandedVmId && state.vms.length > 0) {
      const vmId = state.vms[0].id;
      setExpandedVmId(vmId);
      actions.selectVm(vmId);
    }
  }, [state.vms]);

  function toggleVm(vmId: string) {
    const opening = expandedVmId !== vmId;
    setExpandedVmId(opening ? vmId : null);
    if (opening) actions.selectVm(vmId);
  }

  function pickSession(vmId: string, session: SessionDto) {
    actions.selectSession(vmId, session.id, session.accountId);
    if (!state.messagesBySession[session.id]) actions.loadMessages(vmId, session.id);
    onSelectSession();
  }

  function newChat(vmId: string, accountId: string) {
    actions.selectSession(vmId, null, accountId);
    onSelectSession();
  }

  const q = query.trim().toLowerCase();
  function matchSession(s: SessionDto): boolean {
    return !q || s.title.toLowerCase().includes(q);
  }

  return (
    <div className={`${className} ${managed || embedded ? '' : 'safe-top'} w-full flex-col border-r border-hairline bg-surface-soft md:w-80`}>
      {(managed || embedded) && (
        <ScreenHeader title="Machines">
          {managed && <Button onClick={() => setConnecting(true)} className="inline-flex items-center gap-1.5 whitespace-nowrap !px-4"><Plus size={16} weight="bold" /> Add</Button>}
        </ScreenHeader>
      )}
      {!managed && !embedded && <div className="flex items-center gap-2.5 px-5 pb-3 pt-5">
        <Logo size={32} />
        <h1 className="text-[15px] font-semibold tracking-tight text-ink">Escanor</h1>
      </div>}

      <div className="px-3 pb-2 pt-3">
        <div className="flex items-center gap-2 rounded-md border border-hairline bg-canvas px-3 py-2 transition focus-within:border-primary">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="shrink-0 text-muted-soft">
            <circle cx="11" cy="11" r="7" stroke="currentColor" strokeWidth="2" />
            <path d="M21 21l-4-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            className="w-full bg-transparent text-base text-ink outline-none placeholder:text-muted-soft md:text-[13px]"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-2.5 pb-4">
        {state.vms.length === 0 && (
          managed ? (
            <DogState
              scene="sleep"
              title="Waiting for a machine"
              text="Put the agent on a server and it shows up here, ready to chat with. Your hub and secret are already set up."
              action={<div className="space-y-2"><Button onClick={() => setConnecting(true)} className="w-full">Connect a machine</Button>{managed.guide_url && <a href={managed.guide_url} target="_blank" rel="noreferrer noopener" className="block text-center text-[13px] text-primary underline">Read the setup guide</a>}</div>}
            />
          ) : (
            <DogState scene="sleep" title="No machines yet" text="Install the agent on a server to see it here." />
          )
        )}
        {state.vms.map((vm) => {
          const sessions = state.sessionsByVm[vm.id] ?? [];
          const expanded = expandedVmId === vm.id;
          const accounts: ClaudeAccount[] = vm.accounts?.length ? vm.accounts : [{ id: 'default', label: 'default' }];
          const multiAccount = accounts.length > 1;

          return (
            <div key={vm.id} className={`mb-2 rounded-xl border bg-surface-card ${expanded ? 'border-primary/40' : 'border-hairline'}`}>
              <button
                onClick={() => toggleVm(vm.id)}
                aria-expanded={expanded}
                className="flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left transition hover:bg-canvas/40"
              >
                <span className="relative flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-canvas text-muted">
                  <Desktop size={22} />
                  <span className={`absolute -right-0.5 -top-0.5 h-3 w-3 rounded-full border-2 border-surface-card ${vm.connected ? 'bg-success' : 'bg-hairline'}`} />
                </span>
                <span className="min-w-0 flex-1"><span className="block truncate text-[15px] font-medium text-ink">{vm.name}</span><span className="block truncate text-[12px] text-muted">{machineStatus(vm)} · {sessions.length} {sessions.length === 1 ? 'chat' : 'chats'}</span></span>
                <svg className={`h-3.5 w-3.5 text-muted-soft transition-transform ${expanded ? 'rotate-90' : ''}`} viewBox="0 0 24 24" fill="none">
                  <path d="M9 6l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>

              {expanded && !multiAccount && (
                <div className="ml-3.5 border-l border-hairline pl-2.5">
                  {!q && <NewChatRow onClick={() => newChat(vm.id, accounts[0].id)} />}
                  {sessions.filter(matchSession).slice(0, q ? undefined : more[vm.id] ?? SESSIONS_FIRST).map((s) => (
                    <SessionRow key={s.id} s={s} active={state.selectedSessionId === s.id} onClick={() => pickSession(vm.id, s)} />
                  ))}
                  {!q && sessions.length > (more[vm.id] ?? SESSIONS_FIRST) && <button type="button" onClick={() => setMore({ ...more, [vm.id]: (more[vm.id] ?? SESSIONS_FIRST) + 20 })} className="w-full rounded-md px-2.5 py-2 text-left text-[13px] text-primary hover:bg-primary/10">Show more</button>}
                  {sessions.length === 0 && <p className="px-2.5 py-2 text-[13px] text-muted-soft">No chats yet. Start one with New chat.</p>}
                </div>
              )}

              {expanded && multiAccount && (
                <div className="ml-3.5 space-y-2 border-l border-hairline pl-2.5">
                  {accounts.map((account) => {
                    const accountSessions = sessions.filter((s) => s.accountId === account.id).filter(matchSession);
                    return (
                      <div key={account.id}>
                        <div className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium uppercase tracking-wide text-muted-soft">
                          <PersonIcon />
                          {account.label}
                        </div>
                        {!q && <NewChatRow onClick={() => newChat(vm.id, account.id)} />}
                        {accountSessions.slice(0, q ? undefined : more[vm.id + account.id] ?? SESSIONS_FIRST).map((s) => (
                          <SessionRow key={s.id} s={s} active={state.selectedSessionId === s.id} onClick={() => pickSession(vm.id, s)} />
                        ))}
                        {!q && accountSessions.length > (more[vm.id + account.id] ?? SESSIONS_FIRST) && <button type="button" onClick={() => setMore({ ...more, [vm.id + account.id]: (more[vm.id + account.id] ?? SESSIONS_FIRST) + 20 })} className="w-full rounded-md px-2.5 py-2 text-left text-[13px] text-primary hover:bg-primary/10">Show more</button>}
                        {accountSessions.length === 0 && !q && <p className="px-2.5 py-1.5 text-[12px] text-muted-soft">No sessions yet</p>}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
        {state.vms.length > 0 && !q && <DogState scene="sit" scale={4} title={state.vms.length === 1 ? 'Your machine is all set' : 'Your machines are all set'} text="Tap one to see its chats, or start a new one." />}
      </div>

      <div className="border-t border-hairline px-2.5 py-2.5">
        {managed ? (
          // Escanor is already installed on a hosted hub and signing out is Escanor's, from the Account tab.
          <button type="button" onClick={() => setConnecting(true)} className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-[13px] text-body transition hover:bg-surface-card">
            <span className="text-base leading-none text-primary">+</span> Connect a machine
          </button>
        ) : (
          <>
            <EscanorConnect />
            <button
              type="button"
              onClick={() => actions.logout()}
              className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-[13px] text-muted transition hover:bg-surface-card hover:text-ink"
            >
              <span className="h-2 w-2 shrink-0" />
              Sign out
            </button>
          </>
        )}
      </div>
      {connecting && <ConnectMachineSheet onClose={() => setConnecting(false)} />}
    </div>
  );
}
