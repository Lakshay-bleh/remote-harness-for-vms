import assert from 'node:assert/strict';
import { test } from 'node:test';

test('the app always uses Escanor’s own server, and forgets a custom one an older version saved', async () => {
  const store = new Map<string, string>([['escanor_api_url', 'https://evil.example/api/v1']]);
  (globalThis as { localStorage?: unknown }).localStorage = { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v), removeItem: (k: string) => void store.delete(k) };
  const { escanorApiBase } = await import('./config');
  assert.equal(escanorApiBase(), 'https://api.escanor.in/api/v1');
  assert.equal(store.has('escanor_api_url'), false); // the saved override was removed, not just ignored
  assert.equal('setEscanorApiBase' in (await import('./config')), false); // and there is no longer a way to set one
});
