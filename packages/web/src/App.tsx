import { useState } from 'react';
import { useStore } from './store';
import Login from './components/Login';
import Sidebar from './components/Sidebar';
import ChatView from './components/ChatView';

export default function App() {
  const { state } = useStore();
  const [pane, setPane] = useState<'sidebar' | 'chat'>('sidebar');

  if (!state.authed) return <Login />;

  return (
    <div className="flex h-[100svh] overflow-hidden bg-canvas text-ink">
      <Sidebar className={`${pane === 'chat' ? 'hidden' : 'flex'} md:flex`} onSelectSession={() => setPane('chat')} />
      <ChatView className={`${pane === 'sidebar' ? 'hidden' : 'flex'} md:flex`} onBack={() => setPane('sidebar')} />
    </div>
  );
}
