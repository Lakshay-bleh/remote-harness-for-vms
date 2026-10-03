import { Bell, ChatCircleText, Code, Desktop, Info, Laptop, PaintBrush, PlugsConnected, ShieldCheck, SignOut, Wallet } from '@phosphor-icons/react';
import { useState } from 'react';
import { describeUsage } from '@remote-harness/shared/escanor';
import { APP_VERSION } from '../../appInfo';
import { escanor } from '../client';
import { loadComputers } from '../computer/storage';
import { useLoad } from '../hooks';
import { useEscanorSession } from '../session';
import { ScreenHeader } from '../ui';
import { AccountPage, UsagePage } from './AccountPages';
import DeveloperPage from './DeveloperPage';
import { AboutPage, LegalDocPage, PrivacyPage } from './InfoPages';
import NotificationsPage from './NotificationsPage';
import { Avatar, ConfirmSheet, Group, Row } from './parts';
import { AppearancePage, ChatDefaultsPage } from './PreferencePages';
import { usePrefs } from './prefs';

type Page = 'root' | 'account' | 'usage' | 'notifications' | 'appearance' | 'chats' | 'developer' | 'privacy' | 'about' | `doc:${string}`;

/**
 * Settings, laid out like a phone's own: who you are at the top, then groups that each open a page. It replaces the old Account
 * screen, which was a single list of a usage bar and a key button.
 */
export default function SettingsView({ onGo }: { onGo: (to: 'computers' | 'machines' | 'connections') => void }) {
  const { user, signOut } = useEscanorSession();
  const [page, setPage] = useState<Page>('root');
  const [from, setFrom] = useState<Page>('privacy');
  const [confirmOut, setConfirmOut] = useState(false);
  const prefs = usePrefs();
  const usage = useLoad(() => escanor.usage(), 120000);
  const u = usage.data ? describeUsage(usage.data) : null;
  const back = () => setPage('root');

  switch (page) {
    case 'account': return <AccountPage onBack={back} />;
    case 'usage': return <UsagePage onBack={back} />;
    case 'notifications': return <NotificationsPage onBack={back} />;
    case 'appearance': return <AppearancePage onBack={back} />;
    case 'chats': return <ChatDefaultsPage onBack={back} />;
    case 'developer': return <DeveloperPage onBack={back} />;
    case 'privacy': return <PrivacyPage onBack={back} onOpenDoc={(k) => { setFrom('privacy'); setPage(`doc:${k}`); }} />;
    case 'about': return <AboutPage onBack={back} onOpenDoc={(k) => { setFrom('about'); setPage(`doc:${k}`); }} />;
  }
  if (page.startsWith('doc:')) return <LegalDocPage docKey={page.slice(4)} onBack={() => setPage(from)} />;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <ScreenHeader title="Settings" />
      <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-8 pt-4">
        <button type="button" onClick={() => setPage('account')} className="flex w-full items-center gap-3.5 rounded-xl border border-hairline bg-surface-card p-3.5 text-left transition active:bg-surface-cream-strong">
          <Avatar name={user?.name} email={user?.email} />
          <span className="min-w-0 flex-1"><span className="block truncate text-[17px] text-ink">{user?.name}</span><span className="block truncate text-sm text-muted">{user?.email}</span></span>
          <span className="text-[13px] text-muted">Account</span>
        </button>

        <Group>
          <Row icon={<Wallet size={18} />} label="Plan and usage" sub={u?.messages} onClick={() => setPage('usage')} />
        </Group>

        <Group title="Preferences">
          <Row icon={<Bell size={18} />} label="Notifications" onClick={() => setPage('notifications')} />
          <Row icon={<PaintBrush size={18} />} label="Appearance and feel" value={prefs.textSize === 'default' ? undefined : prefs.textSize === 'small' ? 'Small text' : 'Large text'} onClick={() => setPage('appearance')} />
          <Row icon={<ChatCircleText size={18} />} label="New chats" sub="Permissions, model and effort" onClick={() => setPage('chats')} />
        </Group>

        <Group title="Connected">
          <Row icon={<Laptop size={18} />} label="Computers" value={loadComputers().length || undefined} onClick={() => onGo('computers')} />
          <Row icon={<Desktop size={18} />} label="Machines" onClick={() => onGo('machines')} />
          <Row icon={<PlugsConnected size={18} />} label="Connections" onClick={() => onGo('connections')} />
        </Group>

        <Group title="More">
          <Row icon={<Code size={18} />} label="Developer" onClick={() => setPage('developer')} />
          <Row icon={<ShieldCheck size={18} />} label="Privacy and legal" onClick={() => setPage('privacy')} />
          <Row icon={<Info size={18} />} label="About" value={APP_VERSION} onClick={() => setPage('about')} />
        </Group>

        <Group>
          <Row icon={<SignOut size={18} />} label="Sign out" danger onClick={() => setConfirmOut(true)} />
        </Group>
      </div>
      {confirmOut && <ConfirmSheet title="Sign out?" body="You will need to sign in again. The computers paired with this phone are removed from it too (you can pair them again any time). Nothing on those computers is changed." action="Sign out" onConfirm={() => void signOut()} onClose={() => setConfirmOut(false)} />}
    </div>
  );
}
