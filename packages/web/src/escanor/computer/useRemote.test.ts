import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { retryDelay, withDeadline } from './useRemote';

describe('retryDelay', () => {
  it('waits longer each time, and gives up after three tries', () => {
    assert.deepEqual([0, 1, 2, 3, 4].map(retryDelay), [1500, 4000, 9000, null, null]);
  });
});

describe('withDeadline', () => {
  it('passes the answer through when it comes in time', async () => {
    assert.equal(await withDeadline(Promise.resolve(7), 50), 7);
  });
  it('rejects with a readable message when it does not', async () => {
    await assert.rejects(withDeadline(new Promise(() => undefined), 10), /took too long/);
  });
  it('passes a failure through unchanged', async () => {
    await assert.rejects(withDeadline(Promise.reject(new Error('nope')), 50), /nope/);
  });
});
