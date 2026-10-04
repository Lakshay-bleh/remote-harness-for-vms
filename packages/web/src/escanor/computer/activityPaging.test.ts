import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { mergeActivity, nextStep, oldest } from './activityPaging';
import type { ActivityItem } from './lib/protocol';

const a = (at: string, id = 'ui.navigate'): ActivityItem => ({ at, capabilityId: id, caller: 'voice', risk: 'read', outcome: 'ok', ms: 5 });

describe('mergeActivity', () => {
  it('keeps newest first and drops repeats when the first page is refreshed', () => {
    const loaded = [a('2026-10-04T10:03:00Z'), a('2026-10-04T10:02:00Z'), a('2026-10-04T10:01:00Z')];
    const fresh = [a('2026-10-04T10:04:00Z'), a('2026-10-04T10:03:00Z')];
    assert.deepEqual(mergeActivity(loaded, fresh).map((x) => x.at.slice(11, 16)), ['10:04', '10:03', '10:02', '10:01']);
  });
  it('appends an older page', () => {
    const merged = mergeActivity([a('2026-10-04T10:03:00Z')], [a('2026-10-04T09:00:00Z'), a('2026-10-04T08:00:00Z')]);
    assert.equal(merged.length, 3);
    assert.equal(oldest(merged), '2026-10-04T08:00:00Z');
  });
  it('keeps two different things that happened at the same moment', () => {
    assert.equal(mergeActivity([a('2026-10-04T10:00:00Z', 'os.open_url')], [a('2026-10-04T10:00:00Z', 'ui.navigate')]).length, 2);
  });
});

describe('nextStep', () => {
  it('reveals what is already loaded before asking for more', () => assert.equal(nextStep(40, 20, true), 'reveal'));
  it('asks the computer for older entries once everything loaded is shown', () => assert.equal(nextStep(40, 40, true), 'fetch'));
  it('stops when there is nothing more, and for an older computer that sent it all', () => {
    assert.equal(nextStep(40, 40, false), 'done');
    assert.equal(nextStep(40, 40, undefined), 'done');
  });
});
