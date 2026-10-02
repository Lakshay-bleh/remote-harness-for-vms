import { BellRinging, DeviceMobile, Lightning, PaperPlaneTilt, Rocket, UsersThree, WarningOctagon } from '@phosphor-icons/react';
import { useEffect, useState } from 'react';
import { escanor, type NotificationPrefs } from '../client';
import { useLoad } from '../hooks';
import { Notice, Spinner } from '../ui';
import { enablePush, pushState, type PushState } from '../push';
import { Group, Page, Row, SwitchRow } from './parts';

const KINDS: Array<{ key: Exclude<keyof NotificationPrefs, 'push_enabled'>; label: string; sub: string; icon: JSX.Element }> = [
  { key: 'emergency_alerts', label: 'Emergency alerts', sub: 'Something serious needs you right now', icon: <WarningOctagon size={18} /> },
  { key: 'server_down', label: 'Machine or server down', sub: 'A computer or server stopped responding', icon: <Lightning size={18} /> },
  { key: 'deployment_approvals', label: 'Approvals needed', sub: 'The assistant wants your OK before it deploys or changes something', icon: <Rocket size={18} /> },
  { key: 'team_pings', label: 'Team messages', sub: 'A teammate sent you a note', icon: <UsersThree size={18} /> },
];

/** Whether this phone can receive alerts, and the buttons to turn them on and to check they arrive. */
function ThisPhone() {
  const server = useLoad(() => escanor.pushStatus().catch(() => null), 0);
  const [state, setState] = useState<PushState | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);
  useEffect(() => { void pushState().then(setState); }, []);

  if (state === null || (server.loading && !server.data)) return null;
  if (state === 'unsupported') return <Notice>Alerts on a phone need the Escanor Android app. Your choices below are saved to your account either way.</Notice>;
  if (state === 'unavailable') return <Notice tone="warn">This version of the app was built without Firebase, so it cannot receive notifications. Install the latest release.</Notice>;
  if (server.data && !server.data.configured) return <Notice>This Escanor server is not set up to send push notifications yet, so nothing can reach your phone. Your choices below are saved and will apply once it is.</Notice>;

  const turnOn = async () => {
    setBusy(true);
    setResult(null);
    setState(await enablePush());
    server.reload();
    setBusy(false);
  };
  const test = async () => {
    setBusy(true);
    setResult(null);
    try {
      const { delivered } = await escanor.sendTestPush();
      setResult(delivered > 0 ? { ok: true, text: 'Sent. It should arrive in a few seconds.' } : { ok: false, text: 'Nothing was delivered. Try turning notifications off and on again.' });
    } catch (e) {
      setResult({ ok: false, text: e instanceof Error ? e.message : 'Could not send the test.' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Group title="On this phone" footer={state === 'denied' ? 'Notifications are blocked for Escanor. Allow them in Android Settings, under Apps, Escanor, Notifications.' : undefined}>
        {state === 'on' ? (
          <>
            <Row icon={<DeviceMobile size={18} />} label="Notifications on this phone" value={<span className="text-success">On</span>} />
            <Row icon={<PaperPlaneTilt size={18} />} label="Send a test notification" onClick={() => void test()} disabled={busy} chevron={false} />
          </>
        ) : state === 'denied' ? (
          <Row icon={<DeviceMobile size={18} />} label="Notifications are blocked" value={<span className="text-error">Blocked</span>} />
        ) : (
          <Row icon={<DeviceMobile size={18} />} label="Turn on notifications" sub="Android will ask for your permission" onClick={() => void turnOn()} disabled={busy} />
        )}
      </Group>
      {result && <Notice tone={result.ok ? 'info' : 'warn'}>{result.text}</Notice>}
    </>
  );
}

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
      <ThisPhone />
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
        </>
      )}
    </Page>
  );
}
