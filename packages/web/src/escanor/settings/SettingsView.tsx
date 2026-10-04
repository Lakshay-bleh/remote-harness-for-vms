import { Bell, ChatCircleText, Code, Desktop, Info, Laptop, LifebuoyIcon, Lock, PaintBrush, PlugsConnected, ShieldCheck, SignOut, UsersThree, Wallet, Waveform } from '@phosphor-icons/react';
import { useState } from 'react';
import { describeUsage } from '@remote-harness/shared/escanor';
import { APP_VERSION } from '../../appInfo';
import BillingPage from '../account/BillingPage';
import DeleteAccountPage from '../account/DeleteAccountPage';
import HelpPage from '../account/HelpPage';
import PrivacyDataPage from '../account/PrivacyDataPage';
import SecurityPage from '../account/SecurityPage';
import WorkspacePage from '../account/WorkspacePage';
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
import VoicePage from './VoicePage';
import { usePrefs } from './prefs';

type Page =
  | 'root' | 'account' | 'usage' | 'billing' | 'workspace' | 'security' | 'delete' | 'data' | 'report' | 'help'
  | 'notifications' | 'appearance' | 'chats' | 'voice' | 'developer' | 'privacy' | 'about'
  | `doc:${string}`;

/**
 * Settings, laid out like a phone's own: who you are at the top, then groups that each open a page. Everything an account needs
 * (plan and billing, team, security, data and help) is here, inside the app: nothing sends the person to the website.
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
  const to = (next: Page) => setPage(next);
  const doc = (origin: Page) => (key: string) => { setFrom(origin); setPage(`doc:${key}`); };

  switch (page) {
    case 'account': return <AccountPage onBack={back} />;
    case 'usage': return <UsagePage onBack={back} onBilling={() => to('billing')} />;
    case 'billing': return <BillingPage onBack={back} onContact={() => to('report')} />;
    case 'workspace': return <WorkspacePage onBack={back} />;
    case 'security': return <SecurityPage onBack={back} onDelete={() => to('delete')} />;
    case 'delete': return <DeleteAccountPage onBack={() => to('security')} onSetUp2fa={() => to('security')} />;
    case 'data': return <PrivacyDataPage onBack={back} />;
    case 'report': return <PrivacyDataPage onBack={back} initialType="grievance" />;
    case 'help': return <HelpPage onBack={back} onOpenDoc={doc('help')} onReport={() => to('report')} />;
    case 'notifications': return <NotificationsPage onBack={back} />;
    case 'appearance': return <AppearancePage onBack={back} />;
    case 'chats': return <ChatDefaultsPage onBack={back} />;
    case 'voice': return <VoicePage onBack={back} />;
    case 'developer': return <DeveloperPage onBack={back} onHelp={() => to('help')} />;
    case 'privacy': return <PrivacyPage onBack={back} onOpenDoc={doc('privacy')} onOpenData={() => to('data')} />;
    case 'about': return <AboutPage onBack={back} onOpenDoc={doc('about')} />;
  }
  if (page.startsWith('doc:')) return <LegalDocPage docKey={page.slice(4)} onBack={() => setPage(from)} />;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <ScreenHeader title="Settings" />
      <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-8 pt-4">
        <button type="button" onClick={() => to('account')} className="flex w-full items-center gap-3.5 rounded-xl border border-hairline bg-surface-card p-3.5 text-left transition active:bg-surface-strong">
          <Avatar name={user?.name} email={user?.email} />
          <span className="min-w-0 flex-1"><span className="block truncate text-[17px] text-ink">{user?.name}</span><span className="block truncate text-sm text-muted">{user?.email}</span></span>
          <span className="text-[13px] text-muted">Account</span>
        </button>

        <Group title="Plan">
          <Row icon={<Wallet size={18} />} label="Plan and billing" onClick={() => to('billing')} />
          <Row icon={<Wallet size={18} />} label="Usage" sub={u?.messages} onClick={() => to('usage')} />
        </Group>

        <Group title="Account">
          <Row icon={<UsersThree size={18} />} label="Workspace and team" onClick={() => to('workspace')} />
          <Row icon={<Lock size={18} />} label="Security" sub="Two-step verification, delete account" onClick={() => to('security')} />
          <Row icon={<ShieldCheck size={18} />} label="Privacy and your data" sub="Choices, copy of your data, requests" onClick={() => to('data')} />
        </Group>

        <Group title="Preferences">
          <Row icon={<Bell size={18} />} label="Notifications" onClick={() => to('notifications')} />
          <Row icon={<PaintBrush size={18} />} label="Appearance and feel" value={prefs.theme === 'system' ? 'Match phone' : prefs.theme === 'dark' ? undefined : prefs.theme === 'light' ? 'Light' : 'Pure black'} onClick={() => to('appearance')} />
          <Row icon={<ChatCircleText size={18} />} label="New chats" sub="Permissions, model and effort" onClick={() => to('chats')} />
          <Row icon={<Waveform size={18} />} label="Voice and phone control" sub="Hey Escanor, calling, controlling your phone" onClick={() => to('voice')} />
        </Group>

        <Group title="Connected">
          <Row icon={<Laptop size={18} />} label="Computers" value={loadComputers().length || undefined} onClick={() => onGo('computers')} />
          <Row icon={<Desktop size={18} />} label="Machines" onClick={() => onGo('machines')} />
          <Row icon={<PlugsConnected size={18} />} label="Connections" onClick={() => onGo('connections')} />
        </Group>

        <Group title="More">
          <Row icon={<LifebuoyIcon size={18} />} label="Help" onClick={() => to('help')} />
          <Row icon={<Code size={18} />} label="Developer" onClick={() => to('developer')} />
          <Row icon={<ShieldCheck size={18} />} label="Privacy and legal" onClick={() => to('privacy')} />
          <Row icon={<Info size={18} />} label="About" value={APP_VERSION} onClick={() => to('about')} />
        </Group>

        <Group>
          <Row icon={<SignOut size={18} />} label="Sign out" danger onClick={() => setConfirmOut(true)} />
        </Group>
      </div>
      {confirmOut && <ConfirmSheet title="Sign out?" body="You will need to sign in again. The computers paired with this phone are removed from it too (you can pair them again any time). Nothing on those computers is changed." action="Sign out" onConfirm={() => void signOut()} onClose={() => setConfirmOut(false)} />}
    </div>
  );
}
