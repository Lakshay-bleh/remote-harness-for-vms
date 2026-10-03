import { FileText, Headset, Lifebuoy, ShieldCheck } from '@phosphor-icons/react';
import { isNative } from '../../api';
import { APP_VERSION } from '../../appInfo';
import { LEGAL_LIST, LegalBody } from '../../legal/LegalBody';
import { Logo } from '../ui';
import { Group, Page, Row } from './parts';

/** Privacy and legal: every document reads inside the app, and your data and requests have their own page. */
export function PrivacyPage({ onBack, onOpenDoc, onOpenData }: { onBack: () => void; onOpenDoc: (key: string) => void; onOpenData: () => void }) {
  return (
    <Page title="Privacy and legal" onBack={onBack}>
      <Group title="Your data" footer="Your choices, a copy of your data, and requests to correct or delete it.">
        <Row icon={<ShieldCheck size={18} />} label="Privacy and your data" onClick={onOpenData} />
      </Group>

      <Group title="Read in the app" footer="Every document is stored in the app, so it reads without a connection.">
        {LEGAL_LIST.map((d) => <Row key={d.key} icon={d.key === 'terms' ? <FileText size={18} /> : d.key === 'support' ? <Lifebuoy size={18} /> : <ShieldCheck size={18} />} label={d.label} onClick={() => onOpenDoc(d.key)} />)}
      </Group>

      <p className="px-1 text-[12px] leading-relaxed text-muted">If you use a hub that someone else runs, ask its operator about access, storage and deletion of your session data. Their notices are theirs, not Escanor’s.</p>
    </Page>
  );
}

/** One legal document, full screen, inside Settings. */
export function LegalDocPage({ docKey, onBack }: { docKey: string; onBack: () => void }) {
  return (
    <Page title={LEGAL_LIST.find((d) => d.key === docKey)?.label ?? 'Legal'} onBack={onBack}>
      <LegalBody docKey={docKey} />
    </Page>
  );
}

export function AboutPage({ onBack, onOpenDoc }: { onBack: () => void; onOpenDoc: (key: string) => void }) {
  return (
    <Page title="About" onBack={onBack}>
      <div className="flex flex-col items-center gap-2 py-4 text-center">
        <Logo size={72} />
        <h2 className="font-display text-2xl text-ink">Escanor</h2>
        <p className="text-sm text-muted">Version {APP_VERSION} · {isNative() ? 'Android' : 'Web'}</p>
      </div>
      <Group>
        <Row icon={<Headset size={18} />} label="Get help" onClick={() => onOpenDoc('support')} />
        <Row icon={<ShieldCheck size={18} />} label="Privacy policy" onClick={() => onOpenDoc('privacy')} />
        <Row icon={<FileText size={18} />} label="Terms of service" onClick={() => onOpenDoc('terms')} />
        <Row icon={<FileText size={18} />} label="About Escanor" onClick={() => onOpenDoc('about')} />
      </Group>
    </Page>
  );
}
