import { CopySimple, DeviceMobile, Key, ShieldCheck, Trash } from '@phosphor-icons/react';
import QRCode from 'qrcode';
import { useEffect, useState } from 'react';
import { escanor } from '../client';
import { useLoad } from '../hooks';
import { Group, Page, Row } from '../settings/parts';
import { Button, Notice, Sheet, Spinner } from '../ui';
import { shareExport } from './dataExport';
import { parseCodeInput } from './security';

const FIELD = 'mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 font-mono text-[18px] tracking-widest text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15';

/** Asks for a code from the authenticator app (or a backup code) and hands back what to send. */
export function CodeSheet({ title, body, action, onSubmit, onClose }: { title: string; body: string; action: string; onSubmit: (code: string) => Promise<void>; onClose: () => void }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const code = parseCodeInput(text);
  return (
    <Sheet title={title} onClose={onClose}>
      <form className="space-y-3" onSubmit={async (e) => {
        e.preventDefault();
        if (!code) return setError('Enter the 6 digits from your authenticator app, or a backup code like ABCD-EFGH.');
        setBusy(true);
        setError(null);
        try {
          await onSubmit(code);
        } catch (err) {
          setError(err instanceof Error ? err.message : 'That did not work.');
          setBusy(false);
        }
      }}>
        <p className="text-sm text-body">{body}</p>
        {error && <Notice tone="error">{error}</Notice>}
        <label className="block text-sm text-body">Code
          <input value={text} onChange={(e) => setText(e.target.value)} inputMode="text" autoComplete="one-time-code" autoCapitalize="characters" autoCorrect="off" spellCheck={false} autoFocus placeholder="123 456" aria-label="Code" className={FIELD} />
        </label>
        <Button type="submit" className="w-full" disabled={busy || !text.trim()}>{busy ? 'Checking…' : action}</Button>
      </form>
    </Sheet>
  );
}

function BackupCodes({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  const [note, setNote] = useState<string | null>(null);
  const text = `Escanor backup codes (each works once)\n\n${codes.join('\n')}\n`;
  return (
    <Sheet title="Your backup codes" onClose={onDone}>
      <div className="space-y-3">
        <Notice tone="warn">Save these now. They are shown once. Each one signs you through once if you lose your phone.</Notice>
        <ul className="grid grid-cols-2 gap-2 rounded-md bg-surface-dark p-3 font-mono text-[15px] text-on-dark">{codes.map((c) => <li key={c}>{c}</li>)}</ul>
        <div className="flex gap-2">
          <Button kind="quiet" className="flex flex-1 items-center justify-center gap-2" onClick={() => void navigator.clipboard.writeText(text).then(() => setNote('Copied.')).catch(() => setNote('Could not copy.'))}><CopySimple size={16} aria-hidden /> Copy</Button>
          <Button kind="quiet" className="flex-1" onClick={() => void shareExport(text, 'escanor-backup-codes.txt').catch(() => setNote('Could not share.'))}>Save or send</Button>
        </div>
        {note && <p className="text-[12px] text-muted">{note}</p>}
        <Button className="w-full" onClick={onDone}>I have saved them</Button>
      </div>
    </Sheet>
  );
}

function Setup({ onClose, onEnabled }: { onClose: () => void; onEnabled: (codes: string[]) => void }) {
  const [setup, setSetup] = useState<{ secret: string; otpauth_uri: string } | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    let live = true;
    escanor.twoFactorSetup().then(async (s) => {
      if (!live) return;
      setSetup(s);
      setQr(await QRCode.toDataURL(s.otpauth_uri, { margin: 3, width: 480, errorCorrectionLevel: 'M' }).catch(() => ''));
    }).catch((e) => live && setError(e instanceof Error ? e.message : 'Could not start the setup.'));
    return () => { live = false; };
  }, []);
  const [verify, setVerify] = useState(false);
  if (verify && setup) {
    return <CodeSheet title="Confirm the code" body="Enter the 6 digits your authenticator app shows for Escanor now." action="Turn on" onClose={onClose} onSubmit={async (code) => onEnabled((await escanor.twoFactorEnable(code)).backup_codes)} />;
  }
  return (
    <Sheet title="Turn on two-step verification" onClose={onClose}>
      <div className="space-y-3">
        {error && <Notice tone="error">{error}</Notice>}
        {!setup && !error && <div className="py-6 text-center"><Spinner /></div>}
        {setup && (
          <>
            <p className="text-sm text-body">1. Open an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password, Aegis…).<br />2. Add an account: scan this code, or type the key.</p>
            {qr && <img src={qr} alt="Setup QR code" className="mx-auto size-56 rounded-xl bg-white p-2" />}
            <Button kind="quiet" className="w-full" onClick={() => { window.location.href = setup.otpauth_uri; }}>Open in my authenticator app</Button>
            <div className="rounded-md bg-surface-card p-3"><p className="text-[12px] text-muted">Setup key</p><p className="break-all font-mono text-[14px] text-ink">{setup.secret.match(/.{1,4}/g)?.join(' ')}</p><button type="button" onClick={() => void navigator.clipboard.writeText(setup.secret).then(() => setCopied(true))} className="mt-1 text-[12px] text-primary">{copied ? 'Copied' : 'Copy key'}</button></div>
            <Button className="w-full" onClick={() => setVerify(true)}>I added it: enter the code</Button>
          </>
        )}
      </div>
    </Sheet>
  );
}

export default function SecurityPage({ onBack, onDelete }: { onBack: () => void; onDelete: () => void }) {
  const status = useLoad(() => escanor.twoFactor(), 0);
  const [mode, setMode] = useState<null | 'setup' | 'disable' | 'codes'>(null);
  const [codes, setCodes] = useState<string[] | null>(null);
  const s = status.data;
  return (
    <Page title="Security" subtitle="Two-step verification and your account" onBack={onBack}>
      {status.error && !s && <Notice tone="error">{status.error}</Notice>}
      {status.loading && !s && <div className="py-8 text-center"><Spinner /></div>}
      {s && (
        <Group title="Two-step verification" footer={s.enabled ? 'A code from your authenticator app is needed to delete your account and to change these settings.' : 'Adds a code from an authenticator app as a second check. It is required to delete your account.'}>
          {s.enabled ? (
            <>
              <Row icon={<ShieldCheck size={18} />} label="On" sub={s.enrolled_at ? `Since ${new Date(s.enrolled_at).toLocaleDateString()}` : undefined} />
              <Row icon={<Key size={18} />} label="Backup codes" value={`${s.backup_codes_left} left`} sub="Get a fresh set (the old ones stop working)" onClick={() => setMode('codes')} />
              <Row icon={<DeviceMobile size={18} />} label="Turn off" danger onClick={() => setMode('disable')} />
            </>
          ) : (
            <Row icon={<ShieldCheck size={18} />} label="Turn on" sub="Authenticator app" onClick={() => setMode('setup')} />
          )}
        </Group>
      )}
      <Group title="Danger zone" footer="Deleting your account is scheduled for 7 days, and you can cancel in that time.">
        <Row icon={<Trash size={18} />} label="Delete account" danger onClick={onDelete} />
      </Group>

      {mode === 'setup' && <Setup onClose={() => setMode(null)} onEnabled={(c) => { setMode(null); setCodes(c); status.reload(); }} />}
      {mode === 'disable' && <CodeSheet title="Turn off two-step verification" body="Enter a code from your authenticator app, or a backup code, to turn it off." action="Turn off" onClose={() => setMode(null)} onSubmit={async (code) => { await escanor.twoFactorDisable(code); setMode(null); status.reload(); }} />}
      {mode === 'codes' && <CodeSheet title="New backup codes" body="Enter a code from your authenticator app. You get 8 new backup codes and the old ones stop working." action="Get new codes" onClose={() => setMode(null)} onSubmit={async (code) => { const r = await escanor.twoFactorBackupCodes(code); setMode(null); setCodes(r.backup_codes); status.reload(); }} />}
      {codes && <BackupCodes codes={codes} onDone={() => setCodes(null)} />}
    </Page>
  );
}
