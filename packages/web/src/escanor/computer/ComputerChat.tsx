import { PencilSimpleLine, Trash } from '@phosphor-icons/react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { inlineText, type Attachment } from '../composer/attachments';
import ChatComposer from '../composer/ChatComposer';
import { DogRunner, DogState } from '../dog/DogState';
import { Sheet } from '../ui';
import { addTurn, dayLabel, loadChats, newChat, remove, saveChats, upsert, type Chat, type Turn } from './chatStore';
import ErrorCard from './ErrorCard';
import { explainFailure } from './errors';
import type { ClientMsg, ServerMsg } from './lib/protocol';

type Request = (msg: ClientMsg) => Promise<ServerMsg[]>;
const uid = () => Math.random().toString(36).slice(2, 10);
/** A chat's text goes to the computer in one message; this is the most it accepts. */
const MAX_CHARS = 4000;
const SUGGESTIONS = ['What is using my memory?', 'Show my containers', 'Volume up', 'Open YouTube'];

/** Which chat each computer's assistant is currently holding in mind, so a different one starts over instead of mixing two. */
const served = new Map<string, string>();

/**
 * Talking to the assistant on one computer. Every chat is kept on the phone, so closing the app or leaving the tab never loses one,
 * and earlier chats are a tap away in the history list.
 */
export interface ChatActions {
  history(): void;
  newChat(): void;
  /** There is something to start over from (the open chat has messages). */
  canNew: boolean;
}

export default function ComputerChat({ computerId, request, online, onAsk, onActions }: { computerId: string; request: Request; online: boolean; onAsk: (groupLabel: string) => Promise<string>; onActions?: (a: ChatActions | null) => void }) {
  const [chats, setChats] = useState<Chat[]>(() => loadChats(computerId));
  // The chat on screen is chosen by id. A chat with no messages yet is a draft: it exists only here, not in the saved list.
  const [activeId, setActiveId] = useState<string>(() => loadChats(computerId)[0]?.id ?? newChat().id);
  const [draft, setDraft] = useState<Chat | null>(() => (loadChats(computerId).length ? null : newChat()));
  // Which chats the computer is still working on: a reply belongs to the chat it was asked in, wherever the person has gone since.
  const [working, setWorking] = useState<Record<string, number>>({});
  const [waited, setWaited] = useState(0);
  const [history, setHistory] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  const live = useRef(true);
  // The request each chat is waiting on. Stop (or deleting the chat) forgets it, so a late reply is dropped instead of landing.
  const asked = useRef(new Map<string, string>());
  const chatsRef = useRef(chats);
  chatsRef.current = chats;
  // `live`: this screen is still showing, so a reply that arrives late does not touch a screen that has gone. Set here, not only cleared,
  // because a development double-mount runs the cleanup once before the screen is really gone.
  useEffect(() => {
    live.current = true;
    return () => void (live.current = false);
  }, []);

  const chat: Chat = chats.find((c) => c.id === activeId) ?? (draft && draft.id === activeId ? draft : draft ?? newChat());
  const busy = working[chat.id] !== undefined;

  useEffect(() => {
    end.current?.scrollIntoView({ block: 'end' });
  }, [chat.turns.length, busy, activeId]);

  // How long the computer has been working on the open chat, so a slow answer never looks like a frozen app.
  useEffect(() => {
    if (!busy) return setWaited(0);
    const started = working[chat.id] ?? Date.now();
    const tick = () => setWaited(Math.floor((Date.now() - started) / 1000));
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [busy, chat.id, working]);

  /** Change one chat by id, wherever it is (the list, or the draft that has not been saved yet), and save the list. */
  const change = useCallback((id: string, edit: (c: Chat) => Chat) => {
    const listed = chatsRef.current.find((c) => c.id === id);
    if (listed) {
      const next = upsert(chatsRef.current, edit(listed));
      chatsRef.current = next;
      setChats(next);
      saveChats(computerId, next);
    } else {
      setDraft((d) => {
        const base = d && d.id === id ? d : { ...newChat(), id };
        const edited = edit(base);
        const next = upsert(chatsRef.current, edited);
        chatsRef.current = next;
        setChats(next);
        saveChats(computerId, next);
        return null;
      });
    }
  }, [computerId]);

  const send = useCallback(
    async (message: string, files: Attachment[]) => {
      const id = chat.id;
      if (working[id] !== undefined || !online) return;
      const names = files.map((f) => f.name);
      const body = inlineText(message, files, MAX_CHARS);
      change(id, (c) => addTurn(c, { who: 'you', text: message || `(${names.join(', ')})`, ...(names.length ? { files: names } : {}), at: Date.now() }));
      if (body === null) {
        change(id, (c) => addTurn(c, { who: 'computer', text: `That is too long for this computer to take in one message (the limit is ${MAX_CHARS.toLocaleString()} characters). Attach a smaller file, or part of it.`, problem: true, at: Date.now() }));
        return;
      }
      setWorking((w) => ({ ...w, [id]: Date.now() }));
      const fresh = served.get(computerId) !== id; // the assistant on the computer is holding a different conversation in mind
      const ask = uid();
      asked.current.set(id, ask);
      let turn: Turn;
      try {
        const out = await request({ t: 'chat', id: ask, text: body, ...(fresh ? { fresh: true } : {}) });
        served.set(computerId, id);
        const reply = out.find((m) => m.t === 'reply' || m.t === 'error');
        const said = reply ? (reply.t === 'reply' ? reply.reply : reply.message) : 'Done.';
        // A reply that is really "that is switched off" (or any other error in words) is shown as an explained error with its fix.
        turn = { who: 'computer', text: said, problem: reply?.t === 'error' || explainFailure(said).ask !== undefined, at: Date.now() };
      } catch (e) {
        turn = { who: 'computer', text: e instanceof Error ? e.message : 'That did not work.', problem: true, at: Date.now() };
      }
      // Stopped, or the chat was deleted while the computer worked: the answer has nowhere to go (and must not bring the chat back).
      if (asked.current.get(id) !== ask) return;
      asked.current.delete(id);
      if (chatsRef.current.some((c) => c.id === id)) change(id, (c) => addTurn(c, turn)); // into the chat it was asked in, even if another is open now
      if (live.current) setWorking((w) => { const { [id]: _done, ...rest } = w; return rest; });
    },
    [chat.id, working, online, change, computerId, request],
  );

  /** Stop waiting on the computer for this chat. The computer may still finish the job; its answer is not shown. */
  const stopWaiting = useCallback((id: string) => {
    if (!asked.current.delete(id)) return;
    setWorking((w) => { const { [id]: _done, ...rest } = w; return rest; });
    change(id, (c) => addTurn(c, { who: 'computer', text: 'Stopped waiting. The computer may still finish what it was doing.', at: Date.now() }));
  }, [change]);

  const open = useCallback((c: Chat) => { setActiveId(c.id); setHistory(false); }, []);
  const startNew = useCallback(() => {
    const fresh = newChat();
    setDraft(fresh);
    setActiveId(fresh.id);
    setHistory(false);
  }, []);

  const deleteChat = useCallback((c: Chat) => {
    asked.current.delete(c.id);
    setWorking((w) => { const { [c.id]: _done, ...rest } = w; return rest; });
    const next = remove(chatsRef.current, c.id);
    chatsRef.current = next;
    setChats(next);
    saveChats(computerId, next);
    if (c.id === chat.id) startNew();
  }, [computerId, chat.id, startNew]);

  // New chat and history live in the section bar above (beside Permissions and Activity), not in a row of their own.
  const canNew = chat.turns.length > 0;
  useEffect(() => {
    onActions?.({ history: () => setHistory(true), newChat: startNew, canNew });
    return () => onActions?.(null);
  }, [onActions, startNew, canNew]);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="min-h-0 flex-1 overflow-y-auto px-4">
        <div className="space-y-3 py-3">
          {chat.turns.length === 0 && (
            <>
              <DogState scene="lick" title="Say something, I’m listening" text="Ask your computer to do anything. It runs on its own hardware; you just see the result." />
              <div className="flex flex-wrap justify-center gap-2">{SUGGESTIONS.map((s) => <button key={s} onClick={() => void send(s, [])} disabled={!online || busy} className="rounded-pill border border-hairline px-3.5 py-1.5 text-sm text-body transition hover:bg-surface-card disabled:opacity-50">{s}</button>)}</div>
            </>
          )}
          {chat.turns.map((t, i) =>
            t.problem ? (
              <div key={i} className="max-w-[94%]"><ErrorCard error={t.text} onAsk={onAsk} /></div>
            ) : (
              <div key={i} className={`flex ${t.who === 'you' ? 'justify-end' : ''}`}>
                <div className={`max-w-[88%] rounded-lg px-4 py-2.5 text-[15px] leading-relaxed ${t.who === 'you' ? 'bg-primary text-on-primary' : 'border border-hairline bg-surface-card text-ink'}`}>
                  <p className="whitespace-pre-wrap">{t.text}</p>
                  {t.files?.length ? <p className={`mt-1 text-[12px] ${t.who === 'you' ? 'text-on-primary/70' : 'text-muted'}`}>Attached: {t.files.join(', ')}</p> : null}
                </div>
              </div>
            ),
          )}
          {busy && (
            <div className="space-y-1">
              <DogRunner label={`Working on your computer… ${waited}s`} />
              {waited >= 20 && <p className="text-center text-[12px] text-muted">Still going. Bigger jobs take a while, and the cloud route adds a moment each way.</p>}
            </div>
          )}
          <div ref={end} />
        </div>
      </div>

      <div className="px-4 pb-3 pt-2">
        <ChatComposer key={chat.id} placeholder={online ? 'Message your computer' : 'Computer offline'} disabled={!online} running={busy} attach="text" onSend={(t, f) => void send(t, f)} onStop={() => stopWaiting(chat.id)} />
      </div>

      {history && (
        <Sheet title="Chats with this computer" onClose={() => setHistory(false)}>
          <div className="space-y-3 pb-2">
            <button type="button" onClick={startNew} className="flex w-full items-center gap-3 rounded-xl border border-hairline px-3.5 py-3 text-left text-[15px] text-ink transition hover:bg-surface-card"><PencilSimpleLine size={18} className="text-primary" />New chat</button>
            {chats.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">Your chats with this computer will be listed here.</p>
            ) : (
              <ul className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline">
                {chats.map((c, i) => (
                  <li key={c.id}>
                    {(i === 0 || dayLabel(chats[i - 1].updatedAt) !== dayLabel(c.updatedAt)) && <p className="bg-surface-soft px-3.5 py-1.5 text-[11px] font-medium uppercase tracking-wide text-muted">{dayLabel(c.updatedAt)}</p>}
                    <div className="flex items-center gap-1 pr-1.5">
                      <button type="button" onClick={() => open(c)} className={`min-w-0 flex-1 px-3.5 py-3 text-left transition hover:bg-surface-card ${c.id === chat.id ? 'bg-surface-card' : ''}`}>
                        <span className="block truncate text-[15px] text-ink">{c.title}</span>
                        <span className="block truncate text-[12px] text-muted">{c.turns.length} message{c.turns.length === 1 ? '' : 's'} · {c.turns.at(-1)?.text.slice(0, 40)}</span>
                      </button>
                      <button type="button" aria-label={`Delete ${c.title}`} onClick={() => deleteChat(c)} className="flex h-9 w-9 items-center justify-center rounded-full text-muted transition hover:bg-surface-strong hover:text-error"><Trash size={18} /></button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </Sheet>
      )}
    </div>
  );
}
