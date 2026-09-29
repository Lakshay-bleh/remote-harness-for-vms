import { useState } from 'react';
import { escanor } from './client';
import { Button, Logo, Notice } from './ui';
import { useEscanorSession } from './session';

export default function Welcome({ onAdvanced }: { onAdvanced: () => void }) {
  const { signInWithGoogle, busy, error, canSignInHere } = useEscanorSession();
  const [devEmail, setDevEmail] = useState('');
  const dev = window.location.hostname === 'localhost';

  return (
    <div className="flex h-[100svh] items-center justify-center bg-canvas px-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex items-center gap-3.5">
          <Logo />
          <div>
            <h1 className="font-display text-[30px] font-medium leading-tight tracking-[-0.01em] text-ink">Escanor</h1>
            <p className="text-sm text-muted">Chat with an AI that works on your accounts and code.</p>
          </div>
        </div>
        <div className="space-y-3 rounded-xl border border-hairline p-6 shadow-panel">
          <p className="text-sm text-body">Sign in once. Everything else — your assistant, its machine and its connections — is set up for you.</p>
          {error && <Notice tone="error">{error}</Notice>}
          {!canSignInHere && <Notice tone="warn">Sign-in from this address is not supported. Open Escanor at app.escanor.in, or use the Android app.</Notice>}
          <Button onClick={() => void signInWithGoogle()} disabled={busy || !canSignInHere} className="w-full">
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
              <input value={devEmail} onChange={(e) => setDevEmail(e.target.value)} placeholder="dev email" className="min-w-0 flex-1 rounded-md border border-hairline px-3 py-2 text-sm" />
              <Button type="submit" kind="quiet">Dev</Button>
            </form>
          )}
        </div>
        <button onClick={onAdvanced} className="mt-5 w-full text-center text-[13px] text-muted hover:text-body">
          I run my own Remote Harness hub
        </button>
      </div>
    </div>
  );
}
