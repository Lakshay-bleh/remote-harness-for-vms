import { ArrowUp, PencilSimpleLine, Stop } from '@phosphor-icons/react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { isThinking, toDisplay } from '@remote-harness/shared/escanor';
import ApprovalCard from './ApprovalCard';
import { escanor } from './client';
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

      <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto px-4 py-5"><div className="mx-auto w-full max-w-3xl space-y-4">
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
          return null;
        })}
        {isThinking(chat.state) && <p className="animate-pulse text-[13px] text-muted">Thinking…</p>}
      </div></div>

      {chat.error && <div className="px-4 pb-2"><Notice tone="error">{chat.error}</Notice></div>}

      <div className="px-4 pb-3 pt-2"><div className="mx-auto w-full max-w-3xl">
        {usable.length > 0 ? (
          <button onClick={onOpenIntegrations} className="mb-2 flex w-full flex-wrap items-center gap-1.5 text-left text-[12px] text-muted">
            <span>Connected:</span>
            {usable.slice(0, 5).map((i) => <span key={i.provider_id} className="rounded-pill bg-surface-card px-2 py-0.5 text-body">{i.name}</span>)}
            {usable.length > 5 && <span>+{usable.length - 5}</span>}
          </button>
        ) : (
          caps.data && <button onClick={onOpenIntegrations} className="mb-2 text-left text-[12px] text-primary underline underline-offset-2">Connect a service so I can work on it</button>
        )}
        <Composer running={chat.state.running} onSend={(t) => void chat.send(t)} onStop={() => void chat.stop()} />
      </div></div>

      {machineOpen && <MachineSheet onClose={() => setMachineOpen(false)} />}
    </div>
  );
}

function Composer({ running, onSend, onStop }: { running: boolean; onSend: (t: string) => void; onStop: () => void }) {
  const [text, setText] = useState('');
  const box = useRef<HTMLTextAreaElement>(null);
  const submit = () => { if (text.trim()) { onSend(text); setText(''); if (box.current) box.current.style.height = 'auto'; } };
  return (
    <form className="mx-auto flex w-full max-w-3xl items-end gap-2 rounded-3xl border border-[#3e3c37] bg-surface-dark-soft py-1.5 pl-4 pr-1.5 transition focus-within:border-primary/60 focus-within:ring-4 focus-within:ring-primary/10" onSubmit={(e) => { e.preventDefault(); submit(); }}>
      <textarea
        ref={box}
        value={text}
        onChange={(e) => { setText(e.target.value); e.target.style.height = 'auto'; e.target.style.height = `${Math.min(e.target.scrollHeight, 160)}px`; }}
        onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && !('ontouchstart' in window)) { e.preventDefault(); submit(); } }}
        rows={1}
        placeholder="Message your assistant"
        aria-label="Message"
        className="max-h-40 min-h-[40px] flex-1 resize-none bg-transparent py-2 text-base text-ink outline-none placeholder:text-muted-soft"
      />
      {running ? (
        <button type="button" onClick={onStop} aria-label="Stop" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-surface-card text-ink transition hover:bg-surface-cream-strong active:scale-90"><Stop size={18} weight="fill" /></button>
      ) : (
        <button type="submit" disabled={!text.trim()} aria-label="Send" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary text-on-primary transition hover:bg-primary-active active:scale-90 disabled:bg-surface-card disabled:text-muted-soft"><ArrowUp size={20} weight="bold" /></button>
      )}
    </form>
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
