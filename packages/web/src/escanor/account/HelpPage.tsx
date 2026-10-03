import { Bug, Copy, FileText, Headset, Lifebuoy } from '@phosphor-icons/react';
import { useState } from 'react';
import { isNative } from '../../api';
import { APP_VERSION } from '../../appInfo';
import { LEGAL_LIST } from '../../legal/LegalBody';
import { loadComputers } from '../computer/storage';
import { escanorApiBase } from '../config';
import { useEscanorSession } from '../session';
import { Group, Page, Row } from '../settings/parts';

/** Help, all inside the app: what to read, how to reach a person (a tracked request), and the details worth sending. */
export default function HelpPage({ onBack, onOpenDoc, onReport }: { onBack: () => void; onOpenDoc: (key: string) => void; onReport: () => void }) {
  const { user } = useEscanorSession();
  const [copied, setCopied] = useState(false);
  const debug = () => [
    `Escanor app ${APP_VERSION}`,
    `Platform: ${isNative() ? 'Android app' : 'browser'}`,
    `Server: ${escanorApiBase()}`,
    `Signed in: ${user ? 'yes' : 'no'}`,
    `Paired computers: ${loadComputers().length}`,
    `Screen: ${window.innerWidth}x${window.innerHeight} @${window.devicePixelRatio}x`,
    `Online: ${navigator.onLine}`,
    `Time: ${new Date().toISOString()}`,
  ].join('\n');
  return (
    <Page title="Help" onBack={onBack}>
      <Group title="Get help" footer="A report is a tracked request: it gets a reference number, is acknowledged and answered within the legal deadline, and you follow it under Privacy and your data. Do not include passwords or tokens.">
        <Row icon={<Headset size={18} />} label="Report a problem or make a complaint" onClick={onReport} />
        <Row icon={<Lifebuoy size={18} />} label="Support and contact" onClick={() => onOpenDoc('support')} />
        <Row icon={<Copy size={18} />} label="Copy debug details" value={copied ? 'Copied' : undefined} sub="No passwords or tokens in it" chevron={false} onClick={() => void navigator.clipboard.writeText(debug()).then(() => { setCopied(true); setTimeout(() => setCopied(false), 2000); })} />
      </Group>
      <Group title="Read in the app">
        {LEGAL_LIST.map((d) => <Row key={d.key} icon={d.key === 'refunds' || d.key === 'terms' ? <FileText size={18} /> : <Bug size={18} />} label={d.label} onClick={() => onOpenDoc(d.key)} />)}
      </Group>
    </Page>
  );
}
