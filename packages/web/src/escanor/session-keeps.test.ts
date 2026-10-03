import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';
import { accessIsStale, escanor, hasStoredSession, SessionEnded } from './client';

class FakeStorage {
  private m = new Map<string, string>();
  getItem(k: string) { return this.m.get(k) ?? null; }
  setItem(k: string, v: string) { this.m.set(k, v); }
  removeItem(k: string) { this.m.delete(k); }
}

/** A tiny Escanor server: which access token is current, and what it says to a refresh. */
function fakeServer(opts: { refreshStatus?: number } = {}) {
  const s = { access: 'a1', refresh: 'r1', n: 1, calls: [] as string[], refreshes: 0 };
  globalThis.fetch = (async (url: string, init: RequestInit = {}) => {
    const path = String(url).replace(/^.*\/api\/v1/, '');
    s.calls.push(path);
    const auth = (init.headers as Record<string, string>)?.authorization;
    const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
    if (path === '/auth/refresh') {
      s.refreshes++;
      await new Promise((r) => setTimeout(r, 5));
      if (opts.refreshStatus) return json(opts.refreshStatus, { detail: 'nope' });
      s.access = `a${++s.n}`;
      return json(200, { access_token: s.access, expires_in: 900 });
    }
    if (auth === `Bearer ${s.access}`) return json(200, { path });
    return json(401, { detail: 'Invalid or expired token' });
  }) as typeof fetch;
  return s;
}

describe('a signed-in phone stays signed in', () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, 'localStorage', { value: new FakeStorage(), configurable: true, writable: true });
  });
  const signIn = (s: { access: string; refresh: string }, expiresIn = 900) => {
    localStorage.setItem('escanor_access', s.access);
    localStorage.setItem('escanor_refresh', s.refresh);
    localStorage.setItem('escanor_access_expires', String(Date.now() + expiresIn * 1000));
  };

  it('renews an expired access token and carries on', async () => {
    const s = fakeServer();
    signIn({ access: 'old', refresh: 'r1' });
    const r = await escanor.notificationPrefs();
    assert.ok(r);
    assert.equal(s.refreshes, 1);
    assert.ok(hasStoredSession());
  });

  it('renews before the token runs out, without a refused request first', async () => {
    const s = fakeServer();
    signIn({ access: 'a1', refresh: 'r1' }, 30); // 30 s left: inside the early-renewal window
    await escanor.notificationPrefs();
    assert.equal(s.refreshes, 1);
    assert.ok(!s.calls.slice(0, s.calls.indexOf('/auth/refresh')).some((c) => c !== '/auth/refresh'), 'no request went out with the dying token');
  });

  it('many requests at the moment of expiry renew once, and none of them signs the person out', async () => {
    const s = fakeServer();
    signIn({ access: 'old', refresh: 'r1' });
    const results = await Promise.allSettled(Array.from({ length: 12 }, () => escanor.notificationPrefs()));
    assert.deepEqual(results.map((r) => r.status), Array(12).fill('fulfilled'));
    assert.equal(s.refreshes, 1);
  });

  it('a request that left with the old token while another renewed it is retried, not treated as a sign-out', async () => {
    const s = fakeServer();
    signIn({ access: 'a1', refresh: 'r1' });
    const realFetch = globalThis.fetch;
    // The first call goes out with a1; before it is answered the server has already moved on (another request renewed it).
    let first = true;
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      if (first && !String(url).includes('/auth/refresh')) {
        first = false;
        s.access = 'a2';
        localStorage.setItem('escanor_access', 'a2'); // the other request saved the new token
        return new Response('{}', { status: 401 });
      }
      return realFetch(url, init);
    }) as typeof fetch;
    assert.ok(await escanor.notificationPrefs());
    assert.ok(hasStoredSession());
  });

  it('signs out only when the server refuses the refresh token itself', async () => {
    fakeServer({ refreshStatus: 401 });
    signIn({ access: 'old', refresh: 'r1' });
    await assert.rejects(escanor.notificationPrefs(), SessionEnded);
    assert.equal(hasStoredSession(), false);
  });

  it('keeps the sign-in when the server is down or busy during a renewal', async () => {
    fakeServer({ refreshStatus: 503 });
    signIn({ access: 'old', refresh: 'r1' });
    await assert.rejects(escanor.notificationPrefs(), (e: Error) => !(e instanceof SessionEnded));
    assert.ok(hasStoredSession());
  });

  it('a 401 that survives a successful renewal is an error, not a sign-out', async () => {
    const s = fakeServer();
    signIn({ access: 'old', refresh: 'r1' });
    globalThis.fetch = (async (url: string) => (String(url).includes('/auth/refresh') ? (s.refreshes++, new Response(JSON.stringify({ access_token: 'fresh', expires_in: 900 }), { status: 200 })) : new Response('{}', { status: 401 }))) as typeof fetch;
    await assert.rejects(escanor.notificationPrefs(), (e: Error) => !(e instanceof SessionEnded));
    assert.ok(hasStoredSession(), 'the refresh token is still there');
  });

  it('knows when an access token is about to end', () => {
    assert.equal(accessIsStale(0, 1000), false);
    assert.equal(accessIsStale(10_000_000, 1000), false);
    assert.equal(accessIsStale(1000 + 60_000, 1000), true);
    assert.equal(accessIsStale(500, 1000), true);
  });
});
