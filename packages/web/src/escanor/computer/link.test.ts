import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { offlineMessage, OFFLINE_AFTER_FAILURES, retryDelayMs, shouldShowOffline } from './link';

describe('retryDelayMs', () => {
  it('starts quick, doubles, and settles at 30 seconds', () => {
    assert.deepEqual([1, 2, 3, 4, 5, 6, 20].map(retryDelayMs), [3000, 6000, 12000, 24000, 30000, 30000, 30000]);
  });
  it('treats nonsense attempts as the first', () => {
    assert.equal(retryDelayMs(0), 3000);
    assert.equal(retryDelayMs(-4), 3000);
  });
});

describe('shouldShowOffline', () => {
  it('forgives one failed request and gives up on the second in a row', () => {
    assert.equal(OFFLINE_AFTER_FAILURES, 2);
    assert.equal(shouldShowOffline(0), false);
    assert.equal(shouldShowOffline(1), false);
    assert.equal(shouldShowOffline(2), true);
  });
});

describe('offlineMessage', () => {
  it('points at the likely cause for the cloud route', () => {
    assert.match(offlineMessage(new Error('The computer did not answer. Is it on and online?'), 'cloud'), /Escanor Desktop is open and signed in/);
  });
  it('keeps a sign-in problem as it is', () => {
    assert.equal(offlineMessage(new Error('Your Escanor session ended. Please sign in again.'), 'cloud'), 'Your Escanor session ended. Please sign in again.');
  });
  it('has something to say when it has nothing', () => {
    assert.ok(offlineMessage(undefined, null).length > 10);
  });
});

import { isRecentlySeen } from '../client';
describe('isRecentlySeen', () => {
  const now = Date.parse('2026-10-03T12:00:00Z');
  it('counts an online computer, and one heard from within ten minutes', () => {
    assert.equal(isRecentlySeen('online', null, now), true);
    assert.equal(isRecentlySeen('offline', '2026-10-03T11:55:00Z', now), true);
  });
  it('does not count one that went quiet long ago, or has never been heard from', () => {
    assert.equal(isRecentlySeen('offline', '2026-10-03T11:40:00Z', now), false);
    assert.equal(isRecentlySeen('offline', null, now), false);
    assert.equal(isRecentlySeen('offline', 'garbage', now), false);
    assert.equal(isRecentlySeen('offline', '2026-10-03T12:30:00Z', now), false); // a clock in the future is not "seen"
  });
});
