import { useEffect, useMemo, useState } from 'react';
import type { ClaudeAccount, SessionDto } from '@remote-harness/shared';
import { useStore } from '../store';

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
      className={`flex w-full flex-col gap-0.5 rounded-lg px-2.5 py-2 text-left transition hover:bg-white/5 ${active ? 'bg-white/[0.07]' : ''}`}
    >
      <span className="flex items-center gap-1.5 truncate text-[13px] text-white/80">
        {s.status === 'active' && <span className="h-1.5 w-1.5 shrink-0 animate-pulseDot rounded-full bg-accent" />}
        <span className="truncate">{s.title}</span>
      </span>
      <span className="truncate text-[11px] text-white/30">{relativeTime(s.lastMessageAt)} ago · {s.cwd}</span>
    </button>
  );
}

function NewChatRow({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="mb-0.5 flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-[13px] text-accent transition hover:bg-accent/10">
      <span className="text-base leading-none">+</span> New chat
    </button>
  );
}

export default function Sidebar({ className, onSelectSession }: { className: string; onSelectSession: () => void }) {
  const { state, actions } = useStore();
  const [expandedVmId, setExpandedVmId] = useState<string | null>(null);
  const [query, setQuery] = useState('');

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
    <div className={`${className} safe-top w-full flex-col border-r border-white/5 bg-base-900 md:w-80`}>
      <div className="flex items-center gap-2.5 px-5 pb-3 pt-5">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent/15 text-accent">
          <svg width="14" height="14" viewBox="0 0 100 100" fill="none">
            <path d="M35 22 L60 50 L35 78" stroke="currentColor" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
            <rect x="60" y="66" width="10" height="20" rx="5" fill="currentColor" />
          </svg>
        </div>
        <h1 className="text-[15px] font-semibold tracking-tight text-white">Remote Harness</h1>
      </div>

      <div className="px-3 pb-2">
        <div className="flex items-center gap-2 rounded-xl bg-white/[0.04] px-3 py-2">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="shrink-0 text-white/30">
            <circle cx="11" cy="11" r="7" stroke="currentColor" strokeWidth="2" />
            <path d="M21 21l-4-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            className="w-full bg-transparent text-[13px] text-white outline-none placeholder:text-white/30"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-2.5 pb-4">
        {state.vms.length === 0 && (
          <p className="px-3 py-6 text-sm text-white/30">No VMs connected yet. Install the agent on a server to see it here.</p>
        )}
        {state.vms.map((vm) => {
          const sessions = state.sessionsByVm[vm.id] ?? [];
          const expanded = expandedVmId === vm.id;
          const accounts: ClaudeAccount[] = vm.accounts?.length ? vm.accounts : [{ id: 'default', label: 'default' }];
          const multiAccount = accounts.length > 1;

          return (
            <div key={vm.id} className="mb-1">
              <button
                onClick={() => toggleVm(vm.id)}
                className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2.5 text-left transition hover:bg-white/5"
              >
                <span className={`h-2 w-2 shrink-0 rounded-full ${vm.connected ? 'bg-emerald-400' : 'bg-white/20'}`} />
                <span className="flex-1 truncate text-sm font-medium text-white/90">{vm.name}</span>
                <svg className={`h-3.5 w-3.5 text-white/30 transition-transform ${expanded ? 'rotate-90' : ''}`} viewBox="0 0 24 24" fill="none">
                  <path d="M9 6l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>

              {expanded && !multiAccount && (
                <div className="ml-3.5 border-l border-white/5 pl-2.5">
                  {!q && <NewChatRow onClick={() => newChat(vm.id, accounts[0].id)} />}
                  {sessions.filter(matchSession).map((s) => (
                    <SessionRow key={s.id} s={s} active={state.selectedSessionId === s.id} onClick={() => pickSession(vm.id, s)} />
                  ))}
                  {sessions.length === 0 && <p className="px-2.5 py-2 text-[13px] text-white/30">No sessions yet</p>}
                </div>
              )}

              {expanded && multiAccount && (
                <div className="ml-3.5 space-y-2 border-l border-white/5 pl-2.5">
                  {accounts.map((account) => {
                    const accountSessions = sessions.filter((s) => s.accountId === account.id).filter(matchSession);
                    return (
                      <div key={account.id}>
                        <div className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium uppercase tracking-wide text-white/35">
                          <PersonIcon />
                          {account.label}
                        </div>
                        {!q && <NewChatRow onClick={() => newChat(vm.id, account.id)} />}
                        {accountSessions.map((s) => (
                          <SessionRow key={s.id} s={s} active={state.selectedSessionId === s.id} onClick={() => pickSession(vm.id, s)} />
                        ))}
                        {accountSessions.length === 0 && !q && <p className="px-2.5 py-1.5 text-[12px] text-white/25">No sessions yet</p>}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
