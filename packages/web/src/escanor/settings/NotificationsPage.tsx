import { BellRinging, Lightning, Rocket, UsersThree, WarningOctagon } from '@phosphor-icons/react';
import { useEffect, useState } from 'react';
import { escanor, type NotificationPrefs } from '../client';
import { useLoad } from '../hooks';
import { Notice, Spinner } from '../ui';
import { Group, Page, SwitchRow } from './parts';

const KINDS: Array<{ key: Exclude<keyof NotificationPrefs, 'push_enabled'>; label: string; sub: string; icon: JSX.Element }> = [
  { key: 'emergency_alerts', label: 'Emergency alerts', sub: 'Something serious needs you right now', icon: <WarningOctagon size={18} /> },
  { key: 'server_down', label: 'Machine or server down', sub: 'A computer or server stopped responding', icon: <Lightning size={18} /> },
  { key: 'deployment_approvals', label: 'Approvals needed', sub: 'The assistant wants your OK before it deploys or changes something', icon: <Rocket size={18} /> },
  { key: 'team_pings', label: 'Team messages', sub: 'A teammate sent you a note', icon: <UsersThree size={18} /> },
];

/**
 * What Escanor may tell this person about. The switches are saved on their account, so the website and this app always agree.
 * Delivery to the phone itself needs push to be set up in the app build; until it is, this says so instead of implying otherwise.
 */
export default function NotificationsPage({ onBack }: { onBack: () => void }) {
  const loaded = useLoad(() => escanor.notificationPrefs(), 0);
  const [prefs, setPrefs] = useState<NotificationPrefs | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { if (loaded.data) setPrefs(loaded.data); }, [loaded.data]);

  // Each switch saves straight away; if the save fails the switch goes back and says why.
  const set = async (patch: Partial<NotificationPrefs>) => {
    const before = prefs;
    if (!before) return;
    setPrefs({ ...before, ...patch });
    setError(null);
    try {
      setPrefs(await escanor.setNotificationPrefs(patch));
    } catch (e) {
      setPrefs(before);
      setError(e instanceof Error ? e.message : 'Could not save that.');
    }
  };

  return (
    <Page title="Notifications" onBack={onBack}>
      {loaded.error && !prefs && <Notice tone="error">{loaded.error}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}
      {loaded.loading && !prefs ? <div className="py-10 text-center"><Spinner /></div> : prefs && (
        <>
          <Group footer="Turning this off silences everything below. Your choices are saved to your Escanor account and shared with the website.">
            <SwitchRow icon={<BellRinging size={18} />} label="Notifications" sub="The master switch" on={prefs.push_enabled} onChange={(v) => void set({ push_enabled: v })} />
          </Group>
          <Group title="Tell me about">
            {KINDS.map((k) => (
              <SwitchRow key={k.key} icon={k.icon} label={k.label} sub={k.sub} on={prefs.push_enabled && prefs[k.key]} disabled={!prefs.push_enabled} onChange={(v) => void set({ [k.key]: v })} />
            ))}
          </Group>
          <Notice>Alerts on this phone need push delivery, which this version of the app does not have yet. Your choices are saved now and will apply the moment it is switched on. Until then you can still see everything inside the app.</Notice>
        </>
      )}
    </Page>
  );
}
