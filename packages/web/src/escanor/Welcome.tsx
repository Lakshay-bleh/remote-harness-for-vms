import { useState } from 'react';
import { escanor } from './client';
import { AuthShell, Button, GoogleIcon, Notice } from './ui';
import { useEscanorSession } from './session';

export default function Welcome({ onAdvanced }: { onAdvanced: () => void }) {
  const { signInWithGoogle, busy, error, canSignInHere } = useEscanorSession();
  const [devEmail, setDevEmail] = useState('');
  const dev = window.location.hostname === 'localhost';

  return (
    <AuthShell
      title="Welcome to Escanor"
      subtitle="Sign in once. Your assistant, its machine and your hub are set up for you."
      footer={<button onClick={onAdvanced} className="text-[13px] text-muted transition hover:text-ink">I run my own Remote Harness hub</button>}
    >
      {error && <Notice tone="error">{error}</Notice>}
      {!canSignInHere && <Notice tone="warn">Sign-in from this address is not supported. Open Escanor at app.escanor.in, or use the Android app.</Notice>}
      <Button kind="quiet" onClick={() => void signInWithGoogle()} disabled={busy || !canSignInHere} className="flex w-full items-center justify-center gap-2.5 py-3">
        {busy ? null : <GoogleIcon />}
        {busy ? 'Opening Google…' : 'Continue with Google'}
      </Button>
      {dev && (
        <form
          className="flex gap-2 pt-1"
          onSubmit={(e) => {
            e.preventDefault();
            void escanor.devLogin(devEmail).then(() => window.location.reload()).catch(() => undefined);
          }}
        >
          <input value={devEmail} onChange={(e) => setDevEmail(e.target.value)} placeholder="dev email" aria-label="Dev email" className="min-w-0 flex-1 rounded-pill border border-hairline bg-canvas px-4 py-2 text-sm outline-none focus:border-primary" />
          <Button type="submit">Dev</Button>
        </form>
      )}
    </AuthShell>
  );
}
