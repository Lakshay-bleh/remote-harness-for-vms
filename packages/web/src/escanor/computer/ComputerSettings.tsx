import { ArrowsClockwise, Cloud, IdentificationCard, PencilSimple, Pulse, Trash, WifiHigh } from '@phosphor-icons/react';
import { useState } from 'react';
import { ChoiceSheet, ConfirmSheet, Group, Page, Row } from '../settings/parts';
import { Spinner } from '../ui';
import { displayName, setComputerPrefs, type ComputerPrefs, type RoutePref } from './computerPrefs';
import RenameSheet from './RenameSheet';
import type { PairedComputer } from './lib/client';

const ROUTES: ReadonlyArray<{ value: RoutePref; label: string; hint: string }> = [
  { value: 'auto', label: 'Automatic', hint: 'Wi-Fi when the computer is on it, otherwise through the cloud' },
  { value: 'cloud', label: 'Cloud only', hint: 'Always through your Escanor account, from anywhere' },
  { value: 'lan', label: 'Wi-Fi only', hint: 'Only when this phone is on the same network. Nothing goes through the cloud' },
];

/** One computer's own settings: its name here, how to reach it, what the phone knows about it, and forgetting it. */
export default function ComputerSettings({ computer, prefs, state, route, onBack, onReconnect, onTest, onRemove }: { computer: PairedComputer; prefs: ComputerPrefs; state: 'connecting' | 'online' | 'offline'; route: 'lan' | 'cloud' | null; onBack: () => void; onReconnect: () => void; onTest: () => Promise<number>; onRemove: () => void }) {
  const [sheet, setSheet] = useState<'rename' | 'route' | 'remove' | null>(null);
  const [test, setTest] = useState<{ busy: boolean; text?: string }>({ busy: false });
  const name = displayName(computer, prefs);

  const runTest = async () => {
    setTest({ busy: true });
    try {
      setTest({ busy: false, text: `Answered in ${await onTest()} ms` });
    } catch {
      setTest({ busy: false, text: 'Did not answer' });
    }
  };

  return (
    <Page title={name} subtitle="Settings for this computer" onBack={onBack}>
      <Group title="Name">
        <Row icon={<PencilSimple size={18} />} label="Name on this phone" value={name} onClick={() => setSheet('rename')} />
      </Group>

      <Group title="Connection" footer="Wi-Fi only never uses the cloud, so it will not work when you are away from home.">
        <Row icon={prefs.route === 'lan' ? <WifiHigh size={18} /> : <Cloud size={18} />} label="How to reach it" value={ROUTES.find((r) => r.value === prefs.route)?.label} onClick={() => setSheet('route')} />
        <Row icon={<Pulse size={18} />} label="Status" value={state === 'online' ? `Connected · ${route === 'lan' ? 'Wi-Fi' : 'cloud'}` : state === 'connecting' ? 'Connecting…' : 'Offline'} />
        <Row icon={<ArrowsClockwise size={18} />} label="Test the connection" value={test.busy ? <Spinner /> : test.text} onClick={() => void runTest()} chevron={false} disabled={test.busy} />
        <Row icon={<ArrowsClockwise size={18} />} label="Reconnect now" onClick={onReconnect} chevron={false} />
      </Group>

      <Group title="About this computer">
        <Row icon={<IdentificationCard size={18} />} label="Its own name" value={computer.name} />
        <Row label="Paired" value={new Date(computer.pairedAt).toLocaleDateString()} />
        <Row label="Works away from home" value={computer.agentId ? 'Yes' : 'No: Wi-Fi only'} />
        <Row label="Wi-Fi addresses" sub={computer.lan.length ? computer.lan.join(', ') : 'None saved'} />
        <Row label="This phone’s ID on it" value={<span className="font-mono">{computer.id.slice(0, 8)}</span>} />
      </Group>

      <Group footer="This only removes it from this phone. To stop this phone being able to control the computer at all, also remove the phone on the computer: Escanor Desktop → Phone → Paired phones.">
        <Row icon={<Trash size={18} />} label="Forget this computer" danger onClick={() => setSheet('remove')} />
      </Group>

      {sheet === 'rename' && <RenameSheet current={prefs.alias} original={computer.name} onSave={(alias) => setComputerPrefs(computer.id, { alias })} onClose={() => setSheet(null)} />}
      {sheet === 'route' && <ChoiceSheet title="How to reach it" options={ROUTES} value={prefs.route} onPick={(route) => setComputerPrefs(computer.id, { route })} onClose={() => setSheet(null)} />}
      {sheet === 'remove' && <ConfirmSheet title={`Forget ${name}?`} body="This phone will no longer control it. You can pair it again any time with a new code." action="Forget" onConfirm={onRemove} onClose={() => setSheet(null)} />}
    </Page>
  );
}
