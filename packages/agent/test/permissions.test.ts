import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { PermissionBroker } from '../src/permissions.ts';

const setup = () => {
  const sent: any[] = [];
  return { sent, broker: new PermissionBroker((m) => sent.push(m)) };
};

describe('PermissionBroker', () => {
  it('sends the request and resolves with the hub decision', async () => {
    const { broker, sent } = setup();
    const p = broker.request('s1', 'Bash', { command: 'ls' }, undefined, new AbortController().signal);
    assert.equal(sent[0].type, 'permission_request');
    broker.resolve(sent[0].requestId, 'allow');
    assert.deepEqual(await p, { behavior: 'allow', message: undefined });
  });

  it('denies immediately when the signal is already aborted (instead of hanging forever)', async () => {
    const { broker } = setup();
    const ac = new AbortController();
    ac.abort();
    const r = await Promise.race([
      broker.request('s1', 'Bash', {}, undefined, ac.signal),
      new Promise((res) => setTimeout(() => res('HUNG'), 200)),
    ]);
    assert.deepEqual(r, { behavior: 'deny', message: 'Interrupted' });
    assert.equal(broker.pendingCount(), 0);
  });

  it('denies and prunes pending requests when their session ends', async () => {
    const { broker } = setup();
    const p1 = broker.request('s1', 'Bash', {}, undefined, new AbortController().signal);
    const p2 = broker.request('s2', 'Bash', {}, undefined, new AbortController().signal);
    broker.dropSession('s1');
    assert.equal((await p1).behavior, 'deny');
    assert.equal(broker.pendingCount(), 1);
    broker.dropSession('s2');
    assert.equal((await p2).behavior, 'deny');
    assert.equal(broker.pendingCount(), 0);
  });

  it('ignores responses for unknown request ids', () => {
    const { broker } = setup();
    broker.resolve('nope', 'allow');
    assert.equal(broker.pendingCount(), 0);
  });
});
