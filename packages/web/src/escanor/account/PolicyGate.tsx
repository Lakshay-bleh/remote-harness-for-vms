import { useState } from 'react';
import { escanor } from '../client';
import { useLoad } from '../hooks';
import { Button, Notice } from '../ui';
import LegalSheet from '../../legal/LegalSheet';
import { POLICY_VERSION } from '../../legal/content';
import { needsAcceptance, needsRulesNotice } from './policy';

const RULES = [
  'Use Escanor only on systems and content you are allowed to use, and follow the Acceptable use policy.',
  'If you break the rules or the law, we may remove content and suspend or close your account.',
  'You are responsible under the law for what you store, share or create, including with the AI features.',
  'We report offences to the authorities where the law requires it.',
];

/** Terms and Privacy acceptance at the current version, and the reminder of the rules every three months. Fails open. */
export default function PolicyGate() {
  const consents = useLoad(() => escanor.consents().catch(() => null), 0);
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [doc, setDoc] = useState<string | null>(null);
  const states = consents.data;
  if (!states) return null;
  const mustAccept = needsAcceptance(states, POLICY_VERSION);
  if (!mustAccept && !needsRulesNotice(states)) return null;

  const record = async (purposes: string[]) => {
    setBusy(true);
    setError(null);
    try {
      for (const p of purposes) await escanor.recordConsent(p, true, POLICY_VERSION);
      consents.reload();
    } catch {
      setError('We could not save that. Please try again.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[75] flex items-end justify-center bg-black/50 p-3 sm:items-center" role="dialog" aria-modal="true" aria-label={mustAccept ? 'Terms and privacy' : 'A reminder of our rules'}>
      <div className="max-h-[90dvh] w-full max-w-md space-y-4 overflow-y-auto rounded-2xl border border-line bg-surface-card p-5">
        <h2 className="font-display text-xl text-ink">{mustAccept ? 'Terms and privacy' : 'A reminder of our rules'}</h2>
        {mustAccept && (
          <p className="text-[14px] leading-relaxed text-body">
            Please read the <button type="button" className="underline" onClick={() => setDoc('terms')}>Terms of service</button> and the{' '}
            <button type="button" className="underline" onClick={() => setDoc('privacy')}>Privacy policy</button>. In short:
          </p>
        )}
        <ul className="space-y-1.5 text-[14px] leading-relaxed text-body-strong">{RULES.map((r) => <li key={r}>• {r}</li>)}</ul>
        {mustAccept && (
          <label className="flex gap-3 text-[14px] leading-relaxed text-ink">
            <input type="checkbox" className="mt-1 size-4 shrink-0" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} />
            <span>I am 18 or older, and I agree to the Terms of service and the Privacy policy.</span>
          </label>
        )}
        {error && <Notice tone="error">{error}</Notice>}
        <Button className="w-full" disabled={busy || (mustAccept && !agreed)} onClick={() => void record(mustAccept ? ['terms', 'privacy_notice', 'rules_notice'] : ['rules_notice'])}>
          {mustAccept ? 'Agree and continue' : 'Got it'}
        </Button>
      </div>
      {doc && <LegalSheet start={doc} onClose={() => setDoc(null)} />}
    </div>
  );
}
