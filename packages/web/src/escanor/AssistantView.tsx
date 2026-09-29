import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { isThinking, toDisplay, type AssistantConversation } from '@remote-harness/shared/escanor';
import ApprovalCard from './ApprovalCard';
import { escanor } from './client';
import { useConversation, useLoad } from './hooks';
import MachineSheet, { machineLabel, machineTone } from './MachineSheet';
import { Button, Md, Notice, Sheet, Spinner } from './ui';

const SUGGESTIONS = ['What can you help me with?', 'Check my latest deployments and tell me if anything is wrong', 'Look at the errors from the last day and find the cause', 'Fix the failing build in my repository'];

export default function AssistantView({ onOpenIntegrations }: { onOpenIntegrations: () => void }) {
  const status = useLoad(() => escanor.status(), 1500);
  const ready = status.data?.ready === true;
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [machineOpen, setMachineOpen] = useState(false);
  const conversations = useLoad(() => (ready ? escanor.conversations() : Promise.resolve([] as AssistantConversation[])), 0, [ready]);
  const caps = useLoad(() => (ready ? escanor.capabilities() : Promise.resolve(null)), 30000, [ready]);

  const created = useCallback((id: string) => { setConversationId(id); conversations.reload(); }, [conversations]);
  const chat = useConversation(conversationId, created);
  const blocks = useMemo(() => toDisplay(chat.state), [chat.state]);
  const scroller = useRef<HTMLDivElement>(null);
  useEffect(() => { scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: 'smooth' }); }, [blocks.length, chat.state.running]);

  if (status.loading && !status.data) return <Centered><Spinner /></Centered>;
  if (!ready) return <Setup message={status.data?.message ?? status.error ?? 'Getting your assistant ready…'} state={status.data?.state} />;

  const usable = (caps.data?.integrations ?? []).filter((i) => i.available_to_assistant);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="flex items-center justify-between gap-2 border-b border-hairline px-4 py-2.5">
        <button onClick={() => setHistoryOpen(true)} className="rounded-md px-2 py-1.5 text-sm text-body hover:bg-surface-card" aria-label="Conversations">History</button>
        <h1 className="min-w-0 truncate font-display text-xl text-ink">{conversations.data?.find((c) => c.id === conversationId)?.title ?? 'Assistant'}</h1>
        <button onClick={() => setMachineOpen(true)} className="flex items-center gap-1.5 rounded-md px-2 py-1.5 text-[12px] text-body hover:bg-surface-card" aria-label="Machine">
          <span className={`h-2 w-2 rounded-full ${machineTone(caps.data?.machine.state ?? 'unknown')}`} />
          {machineLabel(caps.data?.machine.state ?? 'unknown').split(' — ')[0]}
        </button>
      </header>

      <div ref={scroller} className="min-h-0 flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {blocks.length === 0 && (
          <div className="mx-auto max-w-md space-y-3 pt-6 text-center">
            <h2 className="font-display text-2xl text-ink">What should we work on?</h2>
            <p className="text-sm text-muted">Ask in your own words. I’ll ask before I change anything.</p>
            <div className="flex flex-col gap-2 pt-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} onClick={() => void chat.send(s)} className="rounded-lg border border-hairline px-3 py-2.5 text-left text-sm text-body hover:bg-surface-card">{s}</button>
              ))}
            </div>
          </div>
        )}
        {blocks.map((b) => {
          if (b.type === 'approval') return <ApprovalCard key={b.key} item={b.item} onAnswer={(allow) => void chat.answer(b.item.request_id, allow)} />;
          if (b.type === 'user') return <div key={b.key} className={`ml-auto max-w-[85%] rounded-xl rounded-br-sm bg-primary px-3.5 py-2.5 text-[15px] text-on-primary ${b.optimistic ? 'opacity-70' : ''}`}>{b.text}</div>;
          if (b.type === 'assistant') return <div key={b.key} className="max-w-[92%]"><Md text={b.text} /></div>;
          if (b.type === 'error') return <Notice key={b.key} tone="error">{b.text}</Notice>;
          if (b.type === 'activity') return <p key={b.key} className={`flex items-center gap-2 text-[13px] text-muted ${b.live ? 'animate-pulse' : ''}`}>{b.live ? <Spinner /> : <span className="text-muted-soft">•</span>}{b.text}</p>;
          return null;
        })}
        {isThinking(chat.state) && <p className="animate-pulse text-[13px] text-muted">Thinking…</p>}
      </div>

      {chat.error && <div className="px-4 pb-2"><Notice tone="error">{chat.error}</Notice></div>}

      <div className="border-t border-hairline px-4 pb-3 pt-2">
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
      </div>

      {historyOpen && (
        <Sheet title="Conversations" onClose={() => setHistoryOpen(false)}>
          <Button className="mb-3 w-full" onClick={() => { setConversationId(null); setHistoryOpen(false); }}>New chat</Button>
          {(conversations.data ?? []).length === 0 && <p className="text-sm text-muted">Your conversations will show up here.</p>}
          <ul className="space-y-1">
            {(conversations.data ?? []).map((c) => (
              <li key={c.id} className="flex items-center gap-2">
                <button onClick={() => { setConversationId(c.id); setHistoryOpen(false); }} className={`min-w-0 flex-1 truncate rounded-md px-3 py-2.5 text-left text-sm hover:bg-surface-card ${c.id === conversationId ? 'bg-surface-card font-medium' : ''}`}>{c.title}</button>
                <button
                  aria-label={`Delete ${c.title}`}
                  onClick={() => { if (window.confirm('Delete this conversation?')) void escanor.remove(c.id).then(() => { if (c.id === conversationId) setConversationId(null); conversations.reload(); }); }}
                  className="rounded-md px-2 py-1.5 text-sm text-muted hover:text-error"
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        </Sheet>
      )}
      {machineOpen && <MachineSheet onClose={() => setMachineOpen(false)} />}
    </div>
  );
}

function Composer({ running, onSend, onStop }: { running: boolean; onSend: (t: string) => void; onStop: () => void }) {
  const [text, setText] = useState('');
  const submit = () => { if (text.trim()) { onSend(text); setText(''); } };
  return (
    <form className="flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); submit(); }}>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && !('ontouchstart' in window)) { e.preventDefault(); submit(); } }}
        rows={1}
        placeholder="Message your assistant"
        aria-label="Message"
        className="max-h-32 min-h-[44px] flex-1 resize-none rounded-lg border border-hairline bg-canvas px-3.5 py-2.5 text-base outline-none focus:border-primary focus:ring-4 focus:ring-primary/15"
      />
      {running ? <Button kind="quiet" onClick={onStop}>Stop</Button> : <Button type="submit" disabled={!text.trim()}>Send</Button>}
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
