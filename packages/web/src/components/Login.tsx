import { useState } from 'react';
import { useStore } from '../store';

export default function Login() {
  const { actions } = useStore();
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await actions.login(password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-[100dvh] items-center justify-center bg-base-950 px-6">
      <form onSubmit={submit} className="w-full max-w-sm rounded-2xl border border-white/5 bg-base-900 p-8 shadow-panel">
        <div className="mb-6 flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-accent/15 text-accent">
            <svg width="18" height="18" viewBox="0 0 100 100" fill="none">
              <path d="M35 22 L60 50 L35 78" stroke="currentColor" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
              <rect x="60" y="66" width="10" height="20" rx="5" fill="currentColor" />
            </svg>
          </div>
          <div>
            <h1 className="text-lg font-semibold text-white">Remote Harness</h1>
            <p className="text-sm text-white/40">Sign in to control your sessions</p>
          </div>
        </div>
        <input
          type="password"
          autoFocus
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Password"
          className="mb-3 w-full rounded-xl border border-white/10 bg-base-800 px-4 py-3 text-sm text-white outline-none placeholder:text-white/30 focus:border-accent/60"
        />
        {error && <p className="mb-3 text-sm text-red-400">{error}</p>}
        <button
          type="submit"
          disabled={busy || !password}
          className="w-full rounded-xl bg-accent px-4 py-3 text-sm font-medium text-base-950 transition hover:bg-accent-soft disabled:opacity-40"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
