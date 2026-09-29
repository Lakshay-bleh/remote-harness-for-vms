import { useEffect, useMemo, useRef, useState } from 'react';
import type { ImageAttachment, MessageDto } from '@remote-harness/shared';
import { useStore } from '../store';
import { api } from '../api';
import { groupMessages } from '../groupMessages';
import Message from './Message';
import Composer from './Composer';
import Dropdown, { Chip } from './Dropdown';

const PERMISSION_MODES = [
  { value: 'default', label: 'Default' },
  { value: 'auto', label: 'Auto' },
  { value: 'acceptEdits', label: 'Accept edits' },
  { value: 'bypassPermissions', label: 'Bypass permissions' },
  { value: 'plan', label: 'Plan mode' },
  { value: 'dontAsk', label: "Don't ask" },
];

const MODEL_OPTIONS = [
  { value: '', label: 'Default model' },
  { value: 'claude-sonnet-5', label: 'Sonnet 5' },
  { value: 'claude-opus-5-5', label: 'Opus 5.5' },
  { value: 'claude-haiku-4-5-20251001', label: 'Haiku 4.5' },
  { value: 'claude-fable-5-1', label: 'Fable 5.1' },
];

const EFFORT_OPTIONS = [
  { value: '', label: 'Default effort' },
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
  { value: 'xhigh', label: 'xHigh' },
  { value: 'max', label: 'Max' },
];

const ServerIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <rect x="3" y="4" width="18" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.8" />
    <rect x="3" y="14" width="18" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.8" />
    <circle cx="7" cy="7" r="1" fill="currentColor" />
    <circle cx="7" cy="17" r="1" fill="currentColor" />
  </svg>
);

const PersonIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <circle cx="12" cy="8" r="4" stroke="currentColor" strokeWidth="2" />
    <path d="M4 20c0-4 3.5-6 8-6s8 2 8 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
  </svg>
);

const ShieldIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
  </svg>
);

const SparkleIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z" fill="currentColor" />
  </svg>
);

const GaugeIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <path d="M4 15a8 8 0 1116 0" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    <path d="M12 15l4-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
  </svg>
);

const FolderIcon = () => (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
    <path d="M3 6a1 1 0 011-1h5l2 2h9a1 1 0 011 1v10a1 1 0 01-1 1H4a1 1 0 01-1-1V6z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
  </svg>
);

function isBusy(rows: MessageDto[]): boolean {
  for (let i = rows.length - 1; i >= 0; i--) {
    const m = rows[i].message as any;
    if (m?.type === 'result') return false;
    if (m?.type === 'user' && m.local) return true;
  }
  return false;
}

export default function ChatView({ className, onBack }: { className: string; onBack: () => void }) {
  const { state, actions } = useStore();
  const { selectedVmId: vmId, selectedSessionId: sessionId, selectedAccountId } = state;
  const scrollRef = useRef<HTMLDivElement>(null);
  const [mode, setMode] = useState('default');
  const [model, setModel] = useState('');
  const [effort, setEffort] = useState('');
  const [project, setProject] = useState('');
  const [projects, setProjects] = useState<string[]>([]);

  useEffect(() => {
    setMode('default');
    setModel('');
    setEffort('');
    setProject('');
  }, [sessionId]);

  useEffect(() => {
    if (!vmId) return;
    setProjects([]);
    api.listProjects(vmId).then(setProjects).catch(() => setProjects([]));
  }, [vmId]);

  const rows = sessionId ? state.messagesBySession[sessionId] ?? [] : [];
  const items = useMemo(() => groupMessages(rows), [rows]);
  const busy = useMemo(() => isBusy(rows), [rows]);
  const vm = state.vms.find((v) => v.id === vmId);
  const session = vmId && sessionId ? (state.sessionsByVm[vmId] ?? []).find((s) => s.id === sessionId) : undefined;
  const accounts = vm?.accounts?.length ? vm.accounts : [{ id: 'default', label: 'default' }];
  const accountId = session?.accountId ?? selectedAccountId ?? accounts[0]?.id;
  const accountLabel = accounts.find((a) => a.id === accountId)?.label ?? accountId;

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [items.length]);

  function handleSend(text: string, images: ImageAttachment[]) {
    if (!vmId) return;
    if (sessionId) actions.sendMessage(vmId, sessionId, text, images);
    else actions.startNewChat(vmId, project || undefined, text, images, accountId);
  }

  const projectOptions = [{ value: '', label: 'Workspace root' }, ...projects.map((p) => ({ value: p, label: p }))];

  if (!vmId) {
    return (
      <div className={`${className} flex-1 flex-col items-center justify-center bg-canvas text-muted-soft`}>
        <p className="text-sm">Select a VM to get started</p>
      </div>
    );
  }

  return (
    <div className={`${className} safe-top flex-1 flex-col bg-canvas`}>
      <div className="flex items-center gap-3 border-b border-hairline px-4 py-3.5">
        <button onClick={onBack} className="-ml-1 flex h-8 w-8 items-center justify-center rounded-md text-muted hover:bg-surface-card md:hidden">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
            <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[14px] font-medium text-ink">{session?.title ?? 'New chat'}</p>
          <p className="truncate text-[12px] text-muted-soft">
            {vm?.name}
            {vm && <span className={`ml-1.5 inline-block h-1.5 w-1.5 rounded-full ${vm.connected ? 'bg-success' : 'bg-hairline'}`} />}
            {session && <span className="ml-1.5">· {session.cwd}</span>}
          </p>
        </div>
      </div>

      <div ref={scrollRef} className="flex-1 space-y-2.5 overflow-y-auto px-4 py-4">
        {items.length === 0 && (
          <div className="flex h-full items-center justify-center text-sm text-muted-soft">
            {sessionId ? 'No messages yet' : `Start a new chat on ${vm?.name}`}
          </div>
        )}
        {items.map((item) => (
          <Message key={item.key} item={item} vmId={vmId} sessionId={sessionId ?? ''} />
        ))}
      </div>

      <Composer
        onSend={handleSend}
        onInterrupt={() => sessionId && actions.interrupt(vmId, sessionId)}
        busy={busy}
        placeholder={sessionId ? 'Message Claude…' : 'Start a new conversation…'}
        onOpenSidebar={onBack}
        topChips={
          <>
            <Chip icon={<ServerIcon />} label={vm?.name ?? ''} />
            <Chip icon={<PersonIcon />} label={accountLabel ?? ''} />
            {!sessionId && (
              <Dropdown
                icon={<FolderIcon />}
                value={project}
                options={projectOptions}
                onChange={setProject}
              />
            )}
            <Dropdown
              icon={<ShieldIcon />}
              value={mode}
              options={PERMISSION_MODES}
              onChange={(v) => {
                setMode(v);
                if (sessionId) actions.setPermissionMode(vmId, sessionId, v);
              }}
            />
          </>
        }
        footerExtra={
          <>
            <Dropdown
              icon={<SparkleIcon />}
              value={model}
              options={MODEL_OPTIONS}
              onChange={(v) => {
                setModel(v);
                if (sessionId) actions.setModel(vmId, sessionId, v);
              }}
            />
            <Dropdown
              icon={<GaugeIcon />}
              value={effort}
              options={EFFORT_OPTIONS}
              onChange={(v) => {
                setEffort(v);
                if (sessionId) actions.setEffort(vmId, sessionId, v);
              }}
            />
          </>
        }
      />
    </div>
  );
}
