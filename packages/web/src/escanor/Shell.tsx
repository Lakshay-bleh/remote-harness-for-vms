import { ChatCircleText, Desktop, GearSix, Laptop, PencilSimpleLine, PlugsConnected, X, type Icon } from '@phosphor-icons/react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { DeletionNotice } from './account/DeleteAccountPage';
import AssistantView from './AssistantView';
import ChatList from './ChatList';
import { useChatMeta } from './chatMeta';
import { useHardwareBack } from './back';
import ComputersView from './computer/ComputersView';
import { escanor } from './client';
import { useLoad } from './hooks';
import IntegrationsView from './IntegrationsView';
import { listenPush, resumePush, type PushDest } from './push';
import { useEscanorSession } from './session';
import SettingsView from './settings/SettingsView';
import { waitForAnswer } from './voice/assistantAnswer';
import VoiceHost from './voice/VoiceOrb';
import { getPrefs, haptic } from './settings/prefs';
import Buddy from './dog/Buddy';
import { Logo, NavContext, useKeyboardOpen } from './ui';

export type Tab = 'assistant' | 'connections' | 'computers' | 'machines' | 'settings';

/** The places, in the order they appear on the phone's tab bar. */
const TABS: Array<{ id: Tab; label: string; Icon: Icon }> = [
  { id: 'assistant', label: 'Chat', Icon: ChatCircleText },
  { id: 'computers', label: 'Computers', Icon: Laptop },
  { id: 'connections', label: 'Connections', Icon: PlugsConnected },
  { id: 'machines', label: 'Machines', Icon: Desktop },
  { id: 'settings', label: 'Settings', Icon: GearSix },
];
const PAGES = TABS.filter((t) => t.id !== 'assistant');

interface NavProps {
  tab: Tab;
  conversationId: string | null;
  conversations: Array<{ id: string; title: string; created_at?: string | null; updated_at?: string | null }>;
  onPick: (t: Tab) => void;
  onNewChat: () => void;
  onOpenChat: (id: string) => void;
  onDeleteChat: (id: string, name: string) => void;
  /** Icons only (tablets) or icons with names and the chat list (desktop). */
  expanded: boolean;
  /** The phone's chat drawer: just new chat and your recent chats. The places are on the tab bar. */
  chatsOnly?: boolean;
}

/** The navigation, laid out like the Claude app: new chat, the places, then your recent chats, then you. */
function Nav({ tab, conversationId, conversations, onPick, onNewChat, onOpenChat, onDeleteChat, expanded, chatsOnly }: NavProps) {
  const { user } = useEscanorSession();
  const hide = expanded ? '' : 'md:hidden';
  const center = expanded ? '' : 'md:justify-center md:px-0';
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className={`flex items-center gap-3 px-5 pb-4 pt-5 ${expanded ? '' : 'md:justify-center md:px-0'}`}>
        <Logo size={34} />
        <span className={`text-[17px] font-semibold tracking-tight text-ink ${hide}`}>{chatsOnly ? 'Chats' : 'Escanor'}</span>
      </div>

      <div className="px-3">
        <button onClick={onNewChat} title="New chat" className={`group flex w-full items-center gap-3 rounded-pill px-3.5 py-2.5 text-[15px] font-medium text-ink outline-none transition hover:bg-surface-card focus-visible:ring-2 focus-visible:ring-primary/50 active:scale-[0.98] ${center}`}>
          <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-on-primary"><PencilSimpleLine size={14} weight="bold" /></span>
          <span className={hide}>New chat</span>
        </button>
      </div>

      {!chatsOnly && (
        <nav aria-label="Main" className="mt-1 flex flex-col gap-0.5 px-3">
          {PAGES.map(({ id, label, Icon }) => {
            const active = tab === id;
            return (
              <button key={id} onClick={() => onPick(id)} aria-current={active ? 'page' : undefined} title={label} className={`flex items-center gap-3 rounded-pill px-3.5 py-2.5 text-[15px] outline-none transition duration-150 focus-visible:ring-2 focus-visible:ring-primary/50 active:scale-[0.98] ${center} ${active ? 'bg-surface-card font-medium text-ink' : 'text-body hover:bg-surface-card/60 hover:text-ink'}`}>
                <Icon size={22} weight={active ? 'fill' : 'regular'} aria-hidden className={active ? 'text-primary' : ''} />
                <span className={hide}>{label}</span>
              </button>
            );
          })}
        </nav>
      )}

      <div className={`mt-4 flex min-h-0 flex-1 flex-col ${hide}`}>
        <ChatList chats={conversations} activeId={tab === 'assistant' ? conversationId : null} onOpen={onOpenChat} onDelete={onDeleteChat} hint={chatsOnly} />
      </div>

      {!chatsOnly && (
        <div className="mt-auto border-t border-hairline px-3 py-3">
          <button onClick={() => onPick('settings')} className={`flex w-full items-center gap-3 rounded-pill p-2 text-left transition hover:bg-surface-card ${expanded ? '' : 'md:justify-center'}`} title={user?.email}>
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-hairline bg-surface-card text-sm font-semibold text-ink">{(user?.name || user?.email || '?').slice(0, 1).toUpperCase()}</span>
            <span className={`min-w-0 ${hide}`}>
              <span className="block truncate text-sm font-medium text-ink">{user?.name}</span>
              <span className="block truncate text-[12px] text-muted">{user?.email}</span>
            </span>
          </button>
        </div>
      )}
    </div>
  );
}

/** The phone's tab bar. It steps aside while the keyboard is up, so typing a message never has it sitting on top of the field. */
function TabBar({ tab, onPick }: { tab: Tab; onPick: (t: Tab) => void }) {
  const keyboard = useKeyboardOpen();
  if (keyboard) return null;
  return (
    <nav aria-label="Main" className="shrink-0 border-t border-hairline bg-surface-soft pb-[env(safe-area-inset-bottom)] md:hidden">
      <ul className="grid grid-cols-5">
        {TABS.map(({ id, label, Icon }) => {
          const active = tab === id;
          return (
            <li key={id}>
              <button onClick={() => { haptic(); onPick(id); }} aria-current={active ? 'page' : undefined} className={`flex w-full flex-col items-center gap-0.5 pb-1.5 pt-2 text-[11px] outline-none transition active:scale-95 ${active ? 'font-medium text-ink' : 'text-muted'}`}>
                <span className={`flex h-7 w-12 items-center justify-center rounded-pill transition ${active ? 'bg-primary/15' : ''}`}>
                  <Icon size={22} weight={active ? 'fill' : 'regular'} aria-hidden className={active ? 'text-primary' : ''} />
                </span>
                {label}
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/**
 * The signed-in app. Phones get a tab bar along the bottom, like any other app, with the list of chats in a drawer from the Chat
 * screen; wider screens keep the sidebar. `machines` is the Remote Harness (hub) view.
 */
export default function Shell({ machines }: { machines: React.ReactNode }) {
  const [start] = useState<Tab>(() => getPrefs().startTab);
  const [tab, setTab] = useState<Tab>(start);
  const tabRef = useRef<Tab>(start);
  tabRef.current = tab;
  // Pressing the tab you are already on takes you back to its first screen (Settings > Billing > Settings tab = Settings, not Billing).
  const [resets, setResets] = useState<Partial<Record<Tab, number>>>({});
  // Screens stay mounted once opened, so going back to one is instant and keeps its place.
  const [visited, setVisited] = useState<Set<Tab>>(() => new Set<Tab>(['assistant', start]));
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [drawer, setDrawer] = useState(false);
  const chats = useLoad(() => escanor.conversations().catch(() => []), 30000);
  const list = chats.data ?? [];
  // An account waiting to be deleted is shown over everything, with the way to keep it.
  const deletion = useLoad(() => escanor.deletionStatus().catch(() => null), 0);
  const meta = useChatMeta();
  const chatName = (id: string | null) => (id ? meta.titles[id] ?? list.find((c) => c.id === id)?.title : undefined);

  const show = useCallback((t: Tab) => { if (tabRef.current === t) setResets((r) => ({ ...r, [t]: (r[t] ?? 0) + 1 })); setTab(t); setVisited((v) => (v.has(t) ? v : new Set(v).add(t))); setDrawer(false); }, []);
  const openChat = useCallback((id: string | null) => { setConversationId(id); if (tabRef.current === 'assistant') setDrawer(false); else show('assistant'); }, [show]);
  /**
   * A voice request for the Escanor assistant: send it into the open conversation (or a new one), wait for the answer, and hand it
   * back to be read out. The chat itself is updated behind voice mode, so closing it lands on the whole conversation.
   */
  const conversationRef = useRef<string | null>(null);
  conversationRef.current = conversationId;
  const askAssistant = useCallback(async (text: string, signal: AbortSignal) => {
    const r = await escanor.send(text, conversationRef.current ?? undefined);
    chats.reload();
    setConversationId(r.conversation_id);
    const a = await waitForAnswer({ fetch: (after) => escanor.messages(r.conversation_id, after), wait: (ms) => new Promise((res) => setTimeout(res, ms)), now: Date.now }, text, { signal });
    if (a.needsApproval) return 'I need your OK to go on. Open the chat to approve it.';
    if (a.timedOut) return 'Still working on it. The answer will be in the chat.';
    return a.text;
  }, [chats]);
  const removeChat = useCallback((id: string, name: string) => {
    if (!window.confirm(`Delete “${name}”? This cannot be undone.`)) return;
    void escanor.remove(id).then(() => { if (id === conversationId) setConversationId(null); chats.reload(); });
  }, [conversationId, chats]);

  // A screen deep inside (the hub page) can ask to be taken to a tab without knowing about this component.
  useEffect(() => {
    const go = (e: Event) => { const to = (e as CustomEvent<Tab>).detail; if (['assistant', 'connections', 'computers', 'machines', 'settings'].includes(to)) show(to); };
    window.addEventListener('escanor-go', go);
    return () => window.removeEventListener('escanor-go', go);
  }, [show]);

  // Push: register this phone again if they already allowed it, take them where a tapped notification points, and show one that
  // arrives while the app is open as a banner (Android shows nothing itself in that case).
  const [banner, setBanner] = useState<{ title: string; body: string; dest: PushDest } | null>(null);
  useEffect(() => {
    void resumePush();
    return listenPush((dest) => show(dest), setBanner);
  }, [show]);
  useEffect(() => {
    if (!banner) return;
    const t = setTimeout(() => setBanner(null), 6000);
    return () => clearTimeout(t);
  }, [banner]);

  // The phone's back button: close the chat list, else leave a tab for Chat, else (nothing left to undo) minimise the app.
  useHardwareBack(drawer, () => setDrawer(false), 2);
  useHardwareBack(!drawer && tab !== 'assistant', () => show('assistant'), 0);

  useEffect(() => {
    if (!drawer) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setDrawer(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [drawer]);

  const navProps = { tab, conversationId, conversations: list, onPick: show, onNewChat: () => openChat(null), onOpenChat: openChat, onDeleteChat: removeChat };
  const screen = (id: Tab, node: React.ReactNode) => visited.has(id) && <div key={resets[id] ?? 0} className={tab === id ? 'h-full' : 'hidden'}>{node}</div>;

  return (
    <NavContext.Provider value={{ open: () => setDrawer(true) }}>
      <VoiceHost go={show} onAssistant={askAssistant}>
      <div className="flex h-[100svh] flex-col overflow-hidden bg-canvas text-ink md:flex-row">
        <aside className="safe-top hidden w-[76px] shrink-0 border-r border-hairline bg-surface-soft md:block lg:w-72">
          <div className="hidden h-full lg:block"><Nav {...navProps} expanded /></div>
          <div className="h-full lg:hidden"><Nav {...navProps} expanded={false} /></div>
        </aside>

        {/* One place keeps clear of the status bar. Screens drawn inside this one (the machines list and its chats) must not add it again. */}
        <main className="safe-top min-h-0 min-w-0 flex-1">
          {screen('assistant', <AssistantView conversationId={conversationId} title={chatName(conversationId)} onConversation={setConversationId} onCreated={chats.reload} onOpenIntegrations={() => show('connections')} />)}
          {screen('connections', <IntegrationsView />)}
          {screen('computers', <ComputersView />)}
          {screen('machines', machines)}
          {screen('settings', <SettingsView onGo={show} />)}
        </main>

        <TabBar tab={tab} onPick={show} />

        {/* the companion: small, in the corner of every screen, running whenever something loads */}
        <Buddy top={48} className="fixed bottom-[calc(env(safe-area-inset-bottom)+72px)] left-1 z-30 md:bottom-3 md:left-auto md:right-3" />

        {deletion.data?.scheduled && <DeletionNotice status={deletion.data} onCancelled={deletion.reload} />}

        {banner && (
          <button type="button" role="status" onClick={() => { show(banner.dest); setBanner(null); }} className="fixed inset-x-3 top-[calc(env(safe-area-inset-top)+8px)] z-[60] rounded-xl border border-line-strong bg-surface-card p-3.5 text-left shadow-elevated md:left-auto md:max-w-sm">
            <span className="block truncate text-[14px] font-medium text-ink">{banner.title}</span>
            {banner.body && <span className="mt-0.5 line-clamp-2 block text-[13px] text-body">{banner.body}</span>}
          </button>
        )}

        {/* Phones: your chats, sliding in from the left. */}
        <div className={`fixed inset-0 z-50 md:hidden ${drawer ? '' : 'pointer-events-none'}`} aria-hidden={!drawer}>
          <div onClick={() => setDrawer(false)} className={`absolute inset-0 bg-black/60 transition-opacity duration-300 ${drawer ? 'opacity-100' : 'opacity-0'}`} />
          <div className={`safe-top absolute inset-y-0 left-0 w-[320px] max-w-[88vw] border-r border-hairline bg-surface-soft shadow-elevated transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] motion-reduce:transition-none ${drawer ? 'translate-x-0' : '-translate-x-full'}`}>
            <button onClick={() => setDrawer(false)} aria-label="Close chats" className="absolute right-3 top-4 z-10 flex h-10 w-10 items-center justify-center rounded-pill text-muted transition hover:bg-surface-card hover:text-ink"><X size={20} /></button>
            <Nav {...navProps} expanded chatsOnly />
          </div>
        </div>
      </div>
      </VoiceHost>
    </NavContext.Provider>
  );
}
