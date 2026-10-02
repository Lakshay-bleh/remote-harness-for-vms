import { Download, FileText, Headset, Lifebuoy, ShieldCheck, Trash } from '@phosphor-icons/react';
import { useState } from 'react';
import { isNative } from '../../api';
import { APP_VERSION } from '../../appInfo';
import { escanor } from '../client';
import { LINKS, openExternal } from '../links';
import { Logo, Notice } from '../ui';
import { Group, Page, Row } from './parts';

/** Privacy, terms and your data. These used to sit in a footer on every screen; a phone app keeps them here, one tap from Settings. */
export function PrivacyPage({ onBack }: { onBack: () => void }) {
  const [state, setState] = useState<{ kind: 'idle' } | { kind: 'busy' } | { kind: 'copied' } | { kind: 'error'; message: string }>({ kind: 'idle' });

  // Android's web view cannot save a downloaded file, so the export goes to the clipboard as JSON.
  const copyData = async () => {
    setState({ kind: 'busy' });
    try {
      await navigator.clipboard.writeText(JSON.stringify(await escanor.exportMyData(), null, 2));
      setState({ kind: 'copied' });
    } catch (e) {
      setState({ kind: 'error', message: e instanceof Error ? e.message : 'Could not export your data.' });
    }
  };

  return (
    <Page title="Privacy and legal" onBack={onBack}>
      <Group title="Escanor">
        <Row icon={<ShieldCheck size={18} />} label="Privacy policy" onClick={() => openExternal(LINKS.privacy)} />
        <Row icon={<FileText size={18} />} label="Terms of service" onClick={() => openExternal(LINKS.terms)} />
        <Row icon={<Lifebuoy size={18} />} label="Support" onClick={() => openExternal(LINKS.support)} />
      </Group>

      <Group title="Your data" footer="A copy of your account details, workspaces and consent history, as JSON on your clipboard. Deleting your account or data is a request you make on the website, so it can be checked and tracked.">
        <Row icon={<Download size={18} />} label="Copy my data" value={state.kind === 'busy' ? 'Working…' : state.kind === 'copied' ? 'Copied' : undefined} onClick={() => void copyData()} chevron={false} disabled={state.kind === 'busy'} />
        <Row icon={<Trash size={18} />} label="Delete my account or data" onClick={() => openExternal(LINKS.accountSettings)} />
      </Group>
      {state.kind === 'error' && <Notice tone="error">{state.message}</Notice>}

      <p className="px-1 text-[12px] leading-relaxed text-muted">If you use a hub that someone else runs, ask its operator about access, storage and deletion of your session data. Their notices are theirs, not Escanor’s.</p>
    </Page>
  );
}

export function AboutPage({ onBack }: { onBack: () => void }) {
  return (
    <Page title="About" onBack={onBack}>
      <div className="flex flex-col items-center gap-2 py-4 text-center">
        <Logo size={72} />
        <h2 className="font-display text-2xl text-ink">Escanor</h2>
        <p className="text-sm text-muted">Version {APP_VERSION} · {isNative() ? 'Android' : 'Web'}</p>
      </div>
      <Group>
        <Row icon={<Headset size={18} />} label="Get help" onClick={() => openExternal(LINKS.support)} />
        <Row icon={<ShieldCheck size={18} />} label="Privacy policy" onClick={() => openExternal(LINKS.privacy)} />
        <Row icon={<FileText size={18} />} label="Terms of service" onClick={() => openExternal(LINKS.terms)} />
      </Group>
    </Page>
  );
}
