import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

const store = new Map<string, string>();
(globalThis as { localStorage?: unknown }).localStorage = {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => void store.set(k, v),
  removeItem: (k: string) => void store.delete(k),
};
const { flushControlConsent, setControlConsent } = await import('./controlConsent');
const { getVoicePrefs } = await import('./voicePrefs');

describe('phone-control consent', () => {
  beforeEach(() => store.clear());

  it('is kept on the phone and sent to the ledger', async () => {
    const sent: boolean[] = [];
    await setControlConsent(true, async (g) => void sent.push(g));
    assert.equal(getVoicePrefs().controlConsent, true);
    assert.deepEqual(sent, [true]);
    assert.equal(store.has('escanor.controlConsent.pending'), false);
  });

  it('waits when it cannot be sent, then sends the latest choice once', async () => {
    await setControlConsent(true, async () => { throw new Error('offline'); });
    await setControlConsent(false, async () => { throw new Error('offline'); });
    assert.equal(getVoicePrefs().controlConsent, false);
    const sent: boolean[] = [];
    await flushControlConsent(async (g) => void sent.push(g));
    await flushControlConsent(async (g) => void sent.push(g));
    assert.deepEqual(sent, [false]);
  });
});
