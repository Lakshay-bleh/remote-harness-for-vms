import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { beginBusy, buddyScene, busyCount, trackBusy } from './busy.ts';

describe('the shared busy count', () => {
  it('goes up while work is running and back down when it ends, even if it fails', async () => {
    assert.equal(busyCount(), 0);
    const end = beginBusy();
    assert.equal(busyCount(), 1);
    end();
    end(); // ending twice must not count twice
    assert.equal(busyCount(), 0);
    await assert.rejects(trackBusy(Promise.reject(new Error('nope'))), /nope/);
    assert.equal(busyCount(), 0);
    const p = trackBusy(new Promise((r) => setTimeout(() => r(1), 5)));
    assert.equal(busyCount(), 1);
    assert.equal(await p, 1);
    assert.equal(busyCount(), 0);
  });
});

describe('which scene the companion plays', () => {
  it('works while anything loads, sleeps when nobody is there, otherwise sits and sniffs', () => {
    assert.equal(buddyScene({ busy: true, asleep: true, sniffing: true }), 'run');
    assert.equal(buddyScene({ busy: false, asleep: true, sniffing: true }), 'sleep');
    assert.equal(buddyScene({ busy: false, asleep: false, sniffing: true }), 'sniff');
    assert.equal(buddyScene({ busy: false, asleep: false, sniffing: false }), 'sit');
  });
});
