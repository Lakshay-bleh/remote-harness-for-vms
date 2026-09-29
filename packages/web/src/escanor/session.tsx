import { App as CapApp } from '@capacitor/app';
import { Browser } from '@capacitor/browser';
import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { isNative } from '../api';
import { APP_SCHEME, loginRedirect } from './config';
import { ApiError, escanor, hasStoredSession, SessionEnded, type EscanorUser } from './client';

type Status = 'loading' | 'signed_out' | 'signed_in';

interface Ctx {
  status: Status;
  user: EscanorUser | null;
  error: string | null;
  busy: boolean;
  /** Start "Continue with Google". Resolves when the browser has been opened (or the page is navigating away). */
  signInWithGoogle(): Promise<void>;
  signOut(): Promise<void>;
  /** A request found the session dead: go back to the sign-in screen. */
  sessionEnded(): void;
  canSignInHere: boolean;
}

const SessionContext = createContext<Ctx | null>(null);

/** `escanor://auth/login?code=...` -> the code (the site's /auth/mobile/login page builds this link). */
export function codeFromDeepLink(url: string): { code?: string; error?: string } | null {
  try {
    const u = new URL(url);
    if (u.protocol !== `${APP_SCHEME}:` || u.hostname !== 'auth') return null;
    return { code: u.searchParams.get('code') ?? undefined, error: u.searchParams.get('error') ?? undefined };
  } catch {
    return null;
  }
}

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<Status>(hasStoredSession() ? 'loading' : 'signed_out');
  const [user, setUser] = useState<EscanorUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const handled = useRef(new Set<string>());
  const redirect = loginRedirect();

  const load = useCallback(async () => {
    try {
      setUser(await escanor.me());
      setStatus('signed_in');
      setError(null);
    } catch (e) {
      if (e instanceof SessionEnded) setStatus('signed_out');
      else if (e instanceof ApiError && e.status === 0 && hasStoredSession()) setStatus('signed_in'); // offline: keep them in
      else {
        setStatus('signed_out');
        setError(e instanceof Error ? e.message : 'Could not sign in.');
      }
    }
  }, []);

  const finishSignIn = useCallback(
    async (code: string) => {
      if (handled.current.has(code)) return; // a login code works once; the same link can arrive twice
      handled.current.add(code);
      setBusy(true);
      try {
        await escanor.exchangeCode(code);
        await load();
      } catch (e) {
        setStatus('signed_out');
        setError(e instanceof Error ? e.message : 'Sign-in failed. Please try again.');
      } finally {
        setBusy(false);
        void Browser.close().catch(() => undefined);
      }
    },
    [load],
  );

  useEffect(() => {
    // Returning from Google in a browser: /auth/callback?code=...
    const params = new URLSearchParams(window.location.search);
    if (window.location.pathname === '/auth/callback' && (params.get('code') || params.get('error'))) {
      window.history.replaceState({}, '', '/');
      if (params.get('code')) void finishSignIn(params.get('code')!);
      else setError('Google sign-in was cancelled.');
      return;
    }
    if (hasStoredSession()) void load();
  }, [finishSignIn, load]);

  useEffect(() => {
    if (!isNative()) return;
    // Returning from Google in the Android app: escanor://auth/login?code=...
    const sub = CapApp.addListener('appUrlOpen', ({ url }) => {
      const link = codeFromDeepLink(url);
      if (!link) return;
      if (link.code) void finishSignIn(link.code);
      else setError('Google sign-in was cancelled.');
    });
    return () => {
      void sub.then((s) => s.remove());
    };
  }, [finishSignIn]);

  const value = useMemo<Ctx>(
    () => ({
      status,
      user,
      error,
      busy,
      canSignInHere: redirect.supported,
      async signInWithGoogle() {
        setError(null);
        setBusy(true);
        try {
          const url = await escanor.authorizeUrl(redirect.uri, isNative() ? 'mobile' : 'web');
          if (isNative()) await Browser.open({ url });
          else window.location.assign(url);
        } catch (e) {
          setError(e instanceof Error ? e.message : 'Could not start sign-in.');
        } finally {
          setBusy(false);
        }
      },
      async signOut() {
        await escanor.signOut();
        setUser(null);
        setStatus('signed_out');
      },
      sessionEnded() {
        setUser(null);
        setStatus('signed_out');
      },
    }),
    [status, user, error, busy, redirect.uri, redirect.supported],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useEscanorSession(): Ctx {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useEscanorSession must be used within SessionProvider');
  return ctx;
}
