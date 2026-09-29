import { useState } from 'react';
import { useStore } from '../store';
import { getHubUrl, isNative, setHubUrl } from '../api';

export default function Login() {
  const { actions } = useStore();
  const native = isNative();
  const [hubUrl, setHubUrlInput] = useState(getHubUrl());
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (native) {
        const url = hubUrl.trim();
        if (!/^https?:\/\//.test(url)) throw new Error('Hub URL must start with http:// or https://');
        setHubUrl(url);
      }
      await actions.login(password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-[100svh] items-center justify-center bg-canvas px-6">
      <form onSubmit={submit} className="w-full max-w-sm rounded-xl border border-hairline bg-canvas p-8 shadow-panel">
        <div className="mb-7 flex items-center gap-3.5">
          <div className="flex h-11 w-11 items-center justify-center rounded-lg bg-surface-dark text-primary">
            <svg width="18" height="18" viewBox="0 0 100 100" fill="none">
              <path d="M35 22 L60 50 L35 78" stroke="currentColor" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
              <rect x="60" y="66" width="10" height="20" rx="5" fill="currentColor" />
            </svg>
          </div>
          <div>
            <h1 className="font-display text-[28px] font-medium leading-tight tracking-[-0.01em] text-ink">Remote Harness</h1>
            <p className="text-sm text-muted">Sign in to control your sessions</p>
          </div>
        </div>
        {native && (
          <input
            type="url"
            inputMode="url"
            autoCapitalize="none"
            autoCorrect="off"
            value={hubUrl}
            onChange={(e) => setHubUrlInput(e.target.value)}
            placeholder="Hub URL (https://hub.example.com)"
            className="mb-3 w-full rounded-md border border-hairline bg-canvas px-4 py-3 text-base text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15"
          />
        )}
        <input
          type="password"
          autoFocus={!native}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Password"
          className="mb-3 w-full rounded-md border border-hairline bg-canvas px-4 py-3 text-base text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15"
        />
        {error && <p className="mb-3 text-sm text-error">{error}</p>}
        <button
          type="submit"
          disabled={busy || !password || (native && !hubUrl)}
          className="w-full rounded-md bg-primary px-4 py-3 text-sm font-medium text-on-primary transition hover:bg-primary-active disabled:opacity-40"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
