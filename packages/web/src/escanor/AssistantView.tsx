import { PencilSimpleLine } from '@phosphor-icons/react';
import { DogSpinner } from './dog/DogState';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { thinkingLabel, toDisplay } from '@remote-harness/shared/escanor';
import ApprovalCard from './ApprovalCard';
import { escanor } from './client';
import ChatComposer from './composer/ChatComposer';
import { useConversation, useLoad } from './hooks';
import MachineSheet, { machineLabel, machineTone } from './MachineSheet';
import { MenuButton, Md, Notice, Spinner } from './ui';

const SUGGESTIONS = ['What can you help me with?', 'Check my latest deployments and tell me if anything is wrong', 'Look at the errors from the last day and find the cause', 'Fix the failing build in my repository'];

export default function AssistantView({ conversationId, title, onConversation, onCreated, onOpenIntegrations }: { conversationId: string | null; title?: string; onConversation: (id: string | null) => void; onCreated: () => void; onOpenIntegrations: () => void }) {
  // Quick while the assistant is starting, then only an occasional check.
  const [wasReady, setWasReady] = useState(false);
  const status = useLoad(() => escanor.status(), wasReady ? 30000 : 1500);
  const ready = status.data?.ready === true;
  useEffect(() => { if (ready) setWasReady(true); }, [ready]);
  const [machineOpen, setMachineOpen] = useState(false);
  const caps = useLoad(() => (ready ? escanor.capabilities() : Promise.resolve(null)), 30000, [ready]);

  const created = useCallback((id: string) => { onConversation(id); onCreated(); }, [onConversation, onCreated]);
  const chat = useConversation(conversationId, created);
  const blocks = useMemo(() => toDisplay(chat.state), [chat.state]);
  const scroller = useRef<HTMLDivElement>(null);
  useEffect(() => { scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: 'smooth' }); }, [blocks.length, chat.state.running]);
  // While a turn runs: what it is doing and for how long, ticking every second. Older servers say nothing, so the time is counted
  // from when this phone first saw it working.
  const working = chat.state.running && chat.state.pending === 0;
  const [now, setNow] = useState(() => Date.now());
  const seenSince = useRef<number | null>(null);
  if (!working) seenSince.current = null;
  else seenSince.current ??= Date.now();
  useEffect(() => {
    if (!working) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [working]);

  if (status.loading && !status.data) return <Centered><Spinner /></Centered>;
  if (!ready) return <Setup message={status.data?.message ?? status.error ?? 'Getting your assistant ready…'} state={status.data?.state} />;

  const usable = (caps.data?.integrations ?? []).filter((i) => i.available_to_assistant);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="flex min-h-[52px] items-center gap-2 border-b border-hairline px-4 py-2.5">
        <MenuButton />
        <h1 className="min-w-0 flex-1 truncate font-display text-xl leading-tight text-ink">{title ?? 'New chat'}</h1>
        <button onClick={() => setMachineOpen(true)} className="flex items-center gap-1.5 rounded-pill px-3 py-1.5 text-[12px] text-body transition hover:bg-surface-card" aria-label="Machine">
          <span className={`h-2 w-2 rounded-full ${machineTone(caps.data?.machine.state ?? 'unknown')}`} />
          {machineLabel(caps.data?.machine.state ?? 'unknown').split(',')[0]}
        </button>
        <button onClick={() => onConversation(null)} aria-label="New chat" title="New chat" className="flex h-9 w-9 items-center justify-center rounded-pill text-body transition hover:bg-surface-card hover:text-ink active:scale-90"><PencilSimpleLine size={20} /></button>
      </header>

      <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto px-4 py-5"><div className="w-full space-y-4">
        {blocks.length === 0 && (
          <div className="mx-auto max-w-md space-y-3 pt-6 text-center">
            <h2 className="font-display text-2xl text-ink">What should we work on?</h2>
            <p className="text-sm text-muted">Ask in your own words. I’ll ask before I change anything.</p>
            <div className="flex flex-col gap-2 pt-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} onClick={() => void chat.send(s)} className="rounded-pill border border-hairline px-4 py-2.5 text-left text-sm text-body transition hover:bg-surface-card hover:text-ink active:scale-[0.99]">{s}</button>
              ))}
            </div>
          </div>
        )}
        {blocks.map((b) => {
          if (b.type === 'approval') return <ApprovalCard key={b.key} item={b.item} onAnswer={(allow) => void chat.answer(b.item.request_id, allow)} />;
          if (b.type === 'user') return <div key={b.key} className={`ml-auto max-w-[85%] rounded-3xl rounded-br-lg bg-surface-card px-4 py-2.5 text-[15px] leading-relaxed text-ink ${b.optimistic ? 'opacity-70' : ''}`}>{b.text}</div>;
          if (b.type === 'assistant') return <div key={b.key} className="max-w-[92%]"><Md text={b.text} /></div>;
          if (b.type === 'error') return <Notice key={b.key} tone="error">{b.text}</Notice>;
          if (b.type === 'activity') return <p key={b.key} className={`flex items-center gap-2 text-[13px] text-muted ${b.live ? 'animate-pulse' : ''}`}>{b.live ? <Spinner /> : <span className="text-muted-soft">•</span>}{b.text}</p>;
          if (b.type === 'notice') return <p key={b.key} className="text-center text-[12px] text-muted-soft">{b.text}</p>;
          return null;
        })}
        {working && <p role="status" aria-live="polite" className="flex items-center gap-2 text-[13px] text-muted"><DogSpinner />{chat.stopping ? 'Stopping…' : thinkingLabel(chat.state.progress, Math.max(now, seenSince.current ?? 0), seenSince.current)}</p>}
      </div></div>

      {chat.error && <div className="px-4 pb-2"><Notice tone="error">{chat.error}</Notice></div>}

      <div className="px-4 pb-3 pt-2"><div className="w-full">
        {usable.length > 0 ? (
          <button onClick={onOpenIntegrations} className="mb-2 flex w-full flex-wrap items-center gap-1.5 text-left text-[12px] text-muted">
            <span>Connected:</span>
            {usable.slice(0, 5).map((i) => <span key={i.provider_id} className="rounded-pill bg-surface-card px-2 py-0.5 text-body">{i.name}</span>)}
            {usable.length > 5 && <span>+{usable.length - 5}</span>}
          </button>
        ) : (
          caps.data && <button onClick={onOpenIntegrations} className="mb-2 text-left text-[12px] text-primary underline underline-offset-2">Connect a service so I can work on it</button>
        )}
        <ChatComposer placeholder="Message your assistant" running={chat.state.running} stopping={chat.stopping} sendWhileRunning={chat.canSend} onSend={(t, files) => void chat.send(t, files)} onStop={() => void chat.stop()} />
      </div></div>

      {machineOpen && <MachineSheet onClose={() => setMachineOpen(false)} />}
    </div>
  );
}

const Centered = ({ children }: { children: React.ReactNode }) => <div className="flex h-full items-center justify-center px-6 text-center">{children}</div>;

function Setup({ message, state }: { message: string; state?: string }) {
  const stuck = state === 'error' || state === 'not_configured';
  return (
    <Centered>
      <div className="max-w-xs space-y-3">
        {!stuck && <Spinner />}
        <h2 className="font-display text-2xl text-ink">{stuck ? 'Your assistant isn’t available yet' : 'Getting your assistant ready'}</h2>
        <p className="text-sm text-muted">{message}</p>
        {!stuck && <p className="text-[12px] text-muted-soft">This happens once, and takes a few seconds.</p>}
      </div>
    </Centered>
  );
}
