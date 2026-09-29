import { useState } from 'react';
import AccountView from './AccountView';
import AssistantView from './AssistantView';
import IntegrationsView from './IntegrationsView';

export type Tab = 'assistant' | 'connections' | 'machines' | 'account';

const TABS: Array<{ id: Tab; label: string; icon: string }> = [
  { id: 'assistant', label: 'Assistant', icon: 'M4 5h16v11H9l-5 4V5z' },
  { id: 'connections', label: 'Connections', icon: 'M9 7V3m6 4V3M7 7h10v5a5 5 0 0 1-10 0V7zm5 10v4' },
  { id: 'machines', label: 'Machines', icon: 'M4 5h16v10H4V5zm4 14h8' },
  { id: 'account', label: 'Account', icon: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-8 8c0-4 3.5-6 8-6s8 2 8 6' },
];

/** The signed-in app: four places, one thumb-reachable bar. `machines` is the Remote Harness (own hub) view. */
export default function Shell({ machines }: { machines: React.ReactNode }) {
  const [tab, setTab] = useState<Tab>('assistant');
  return (
    <div className="flex h-[100svh] flex-col overflow-hidden bg-canvas text-ink">
      <main className="safe-top min-h-0 flex-1">
        {tab === 'assistant' && <AssistantView onOpenIntegrations={() => setTab('connections')} />}
        {tab === 'connections' && <IntegrationsView />}
        {tab === 'machines' && <div className="h-full">{machines}</div>}
        {tab === 'account' && <AccountView onOpenMachines={() => setTab('machines')} />}
      </main>
      <nav className="flex border-t border-hairline bg-canvas pb-[env(safe-area-inset-bottom)]" aria-label="Main">
        {TABS.map((t) => (
          <button key={t.id} onClick={() => setTab(t.id)} aria-current={tab === t.id ? 'page' : undefined} className={`flex flex-1 flex-col items-center gap-0.5 py-2 text-[11px] ${tab === t.id ? 'text-primary' : 'text-muted'}`}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d={t.icon} /></svg>
            {t.label}
          </button>
        ))}
      </nav>
    </div>
  );
}
