import { Warning } from '@phosphor-icons/react';
import { useState } from 'react';
import { escanor, type DeletionStatus } from '../client';
import { useLoad } from '../hooks';
import { useEscanorSession } from '../session';
import { Page } from '../settings/parts';
import { Button, Notice, Sheet, Spinner } from '../ui';
import { daysUntil, DELETION_FACTS, emailConfirmed, parseCodeInput } from './security';

const FIELD = 'mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-[15px] text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15';

/** Delete the account: confirmed with the account email (and a code when two-step verification is on), scheduled for a week so it can be taken back. */
export default function DeleteAccountPage({ onBack }: { onBack: () => void; onSetUp2fa?: () => void }) {
  const { user, signOut } = useEscanorSession();
  const status = useLoad(() => escanor.deletionStatus(), 0);
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<DeletionStatus | null>(null);
  const s = status.data;
  const parsed = parseCodeInput(code);
  const needsCode = Boolean(status.data?.two_factor_enabled);
  const ready = emailConfirmed(email, user?.email) && (!needsCode || Boolean(parsed));

  const submit = async () => {
    if (needsCode && !parsed) return;
    setBusy(true);
    setError(null);
    try {
      setDone(await escanor.requestDeletion(needsCode ? parsed : null, email.trim()));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That did not work. Nothing was changed.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Page title="Delete account" onBack={onBack}>
      {status.loading && !s && <div className="py-8 text-center"><Spinner /></div>}
      {status.error && !s && <Notice tone="error">{status.error}</Notice>}
      {s?.scheduled && (
        <Notice tone="warn">Your account is already scheduled for deletion {s.scheduled_for ? daysUntil(s.scheduled_for) : ''}. You can cancel it when you open the app.</Notice>
      )}
      {s && !s.scheduled && (
        <>
          <section className="space-y-2 rounded-xl border border-error/30 bg-error/5 p-4">
            <h2 className="flex items-center gap-2 font-display text-lg text-error"><Warning size={20} weight="fill" aria-hidden /> What happens</h2>
            <ul className="space-y-2 text-[13.5px] leading-relaxed text-body-strong">{DELETION_FACTS.map((f) => <li key={f}>• {f}</li>)}</ul>
          </section>
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); if (ready) void submit(); }}>
            {error && <Notice tone="error">{error}</Notice>}
            <label className="block text-sm text-body">Type your email to confirm ({user?.email})
              <input value={email} onChange={(e) => setEmail(e.target.value)} inputMode="email" autoCapitalize="none" autoCorrect="off" spellCheck={false} className={FIELD} aria-label="Account email" />
            </label>
            {needsCode && (
              <label className="block text-sm text-body">Code from your authenticator app (or a backup code)
                <input value={code} onChange={(e) => setCode(e.target.value)} autoComplete="one-time-code" autoCapitalize="characters" autoCorrect="off" spellCheck={false} placeholder="123 456" className={`${FIELD} font-mono tracking-widest`} aria-label="Code" />
              </label>
            )}
            <Button kind="danger" type="submit" className="w-full" disabled={!ready || busy}>{busy ? 'Scheduling…' : 'Delete my account'}</Button>
          </form>
        </>
      )}
      {done && (
        <Sheet title="Deletion scheduled" onClose={() => void signOut()}>
          <div className="space-y-3 text-sm text-body">
            <p>Your account will be deleted {done.scheduled_for ? `on ${new Date(done.scheduled_for).toLocaleDateString()}` : 'in 7 days'}. You have been signed out everywhere.</p>
            <p>Changed your mind? Sign in again before then and choose to keep your account. Reference: <b className="font-mono text-ink">{done.reference}</b></p>
            <Button className="w-full" onClick={() => void signOut()}>OK</Button>
          </div>
        </Sheet>
      )}
    </Page>
  );
}

/** Shown over the app when the signed-in account is waiting to be deleted. */
export function DeletionNotice({ status, onCancelled }: { status: DeletionStatus; onCancelled: () => void }) {
  const { signOut } = useEscanorSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-canvas p-6" role="alertdialog" aria-label="Account scheduled for deletion">
      <div className="w-full max-w-sm space-y-4 text-center">
        <Warning size={40} weight="fill" className="mx-auto text-warning" aria-hidden />
        <h2 className="font-display text-2xl text-ink">Your account will be deleted {status.scheduled_for ? daysUntil(status.scheduled_for) : 'soon'}</h2>
        <p className="text-sm text-body">You asked to delete it{status.scheduled_for ? `, due on ${new Date(status.scheduled_for).toLocaleDateString()}` : ''}. Until then you can keep it by cancelling the deletion.</p>
        {error && <Notice tone="error">{error}</Notice>}
        <Button className="w-full" disabled={busy} onClick={async () => { setBusy(true); try { await escanor.cancelDeletion(); onCancelled(); } catch (e) { setError(e instanceof Error ? e.message : 'Could not cancel.'); setBusy(false); } }}>{busy ? 'Cancelling…' : 'Keep my account'}</Button>
        <Button kind="quiet" className="w-full" onClick={() => void signOut()}>Sign out</Button>
      </div>
    </div>
  );
}
