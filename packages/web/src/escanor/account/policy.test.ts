import assert from 'node:assert/strict';
import { test } from 'node:test';
import { needsAcceptance, needsRulesNotice } from './policy';

const s = (purpose: string, version = 'v2', recorded_at = '2026-10-01T00:00:00Z') => ({ purpose, granted: true, notice_version: version, recorded_at });

test('acceptance is needed until both records exist at the current version', () => {
  assert.equal(needsAcceptance([], 'v2'), true);
  assert.equal(needsAcceptance([s('terms')], 'v2'), true);
  assert.equal(needsAcceptance([s('terms'), s('privacy_notice')], 'v2'), false);
  assert.equal(needsAcceptance([s('terms', 'v1'), s('privacy_notice', 'v1')], 'v2'), true);
});

test('the rules reminder comes back after 90 days', () => {
  const now = new Date('2026-10-07T00:00:00Z');
  assert.equal(needsRulesNotice([], now), true);
  assert.equal(needsRulesNotice([s('rules_notice', 'x', '2026-09-01T00:00:00Z')], now), false);
  assert.equal(needsRulesNotice([s('rules_notice', 'x', '2026-06-01T00:00:00Z')], now), true);
});

test('a newer version accepted elsewhere (website, desktop) counts: an app one version behind must not ask again', () => {
  assert.equal(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-08')], '2026-10-07'), false);
  assert.equal(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-06')], '2026-10-07'), true);
});

test('the highest accepted version counts, so an older client recording its version afterwards does not re-ask', () => {
  const after = (p: string) => ({ ...s(p, '2026-10-08'), accepted_version: '2026-10-10' });
  assert.equal(needsAcceptance([after('terms'), after('privacy_notice')], '2026-10-10'), false);
  assert.equal(needsAcceptance([after('terms'), after('privacy_notice')], '2026-10-11'), true);
  assert.equal(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-08')], '2026-10-10'), true);
});
