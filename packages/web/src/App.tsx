import { useEffect, useState } from 'react';
import { useStore } from './store';
import Login from './components/Login';
import Sidebar from './components/Sidebar';
import ChatView from './components/ChatView';
import Shell from './escanor/Shell';
import Welcome from './escanor/Welcome';
import { hasStoredSession } from './escanor/client';
import ManagedMachines from './escanor/ManagedMachines';
import { clearManaged, isManaged } from './escanor/managed';
import { hubSocket } from './ws';
import { SessionProvider, useEscanorSession } from './escanor/session';
import { useHardwareBack } from './escanor/back';
import { EmbeddedContext, Logo, Spinner } from './escanor/ui';

/** The Remote Harness: sessions on machines you run yourself, through your own hub. Unchanged behaviour. */
function HubApp({ embedded = false, onBack }: { embedded?: boolean; onBack?: () => void }) {
  const { state } = useStore();
  const [pane, setPane] = useState<'sidebar' | 'chat'>('sidebar');
  // On a phone the machine's chat is a step inside the machines list: the back button returns to the list.
  useHardwareBack(state.authed && pane === 'chat', () => setPane('sidebar'));

  if (!state.authed) {
    return (
      <EmbeddedContext.Provider value={embedded}>
        <div className="relative h-full">
          <Login />
          {onBack && <button onClick={onBack} className="absolute left-4 top-4 rounded-md px-3 py-2 text-sm text-muted hover:bg-surface-card">← Back to Escanor</button>}
        </div>
      </EmbeddedContext.Provider>
    );
  }
  return (
    <EmbeddedContext.Provider value={embedded}>
      <div className={`flex overflow-hidden bg-canvas text-ink ${embedded ? 'h-full' : 'h-[100svh]'}`}>
        <Sidebar className={`${pane === 'chat' ? 'hidden' : 'flex'} md:flex`} onSelectSession={() => setPane('chat')} />
        <ChatView className={`${pane === 'sidebar' ? 'hidden' : 'flex'} md:flex`} onBack={() => setPane('sidebar')} />
      </div>
    </EmbeddedContext.Provider>
  );
}

function Root() {
  const session = useEscanorSession();
  const { state, actions } = useStore();
  // Someone who only ever used their own hub keeps landing there, exactly as before. Credentials of Escanor's
  // hosted hub are not "their own hub": without an Escanor sign-in they are never shown.
  const [ownHub, setOwnHub] = useState(state.authed && !hasStoredSession() && !isManaged());

  // Signing out of Escanor takes the hosted hub's credentials -- and the last person's chats -- with it.
  useEffect(() => {
    if (session.status === 'signed_out' && clearManaged()) {
      hubSocket.stop();
      actions.dispatch({ type: 'set_authed', authed: false });
    }
  }, [session.status, actions]);

  if (ownHub) return <HubApp onBack={() => setOwnHub(false)} />;
  if (session.status === 'loading') {
    return <div className="flex h-[100svh] items-center justify-center bg-canvas"><div className="flex flex-col items-center gap-4"><Logo /><Spinner /></div></div>;
  }
  if (session.status === 'signed_out') return <Welcome onAdvanced={() => setOwnHub(true)} />;
  return (
    <Shell
      machines={
        <ManagedMachines fallback={<HubApp embedded />}>
          <HubApp embedded />
        </ManagedMachines>
      }
    />
  );
}

export default function App() {
  return (
    <SessionProvider>
      <Root />
    </SessionProvider>
  );
}
