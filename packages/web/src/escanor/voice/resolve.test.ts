import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { resolveOnServer } from './resolve';
import type { ServerPlan } from './serverPlan';

const plan: ServerPlan = { source: 'rules', say: 'Okay.', actions: [], needs: null };

describe('resolveOnServer', () => {
  it('says which phone it is (an iPhone is not an Android phone)', async () => {
    const sent: Array<{ platform: string }> = [];
    const send = async (body: { device: { platform: string } }) => (sent.push(body.device), plan);
    await resolveOnServer('hi', null, { send, ios: true, signedIn: () => true });
    await resolveOnServer('hi', null, { send, ios: false, signedIn: () => true });
    assert.deepEqual(sent.map((d) => d.platform), ['ios', 'android']);
  });

  it('passes the turn’s signal on, so cancelling voice cancels the request', async () => {
    const ctl = new AbortController();
    let got: AbortSignal | undefined;
    await resolveOnServer('hi', null, { send: async (_b, signal) => ((got = signal), plan), signal: ctl.signal, ios: false, signedIn: () => true });
    assert.equal(got, ctl.signal);
  });

  it('is null when signed out, or when anything goes wrong', async () => {
    assert.equal(await resolveOnServer('hi', null, { send: async () => plan, signedIn: () => false }), null);
    assert.equal(await resolveOnServer('hi', null, { send: async () => { throw new Error('offline'); }, signedIn: () => true }), null);
  });
});
