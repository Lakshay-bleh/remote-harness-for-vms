import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_PREFS, parsePrefs, TEXT_SIZE_PERCENT } from './prefs';

test('nothing stored gives the defaults', () => {
  assert.deepEqual(parsePrefs(null), DEFAULT_PREFS);
  assert.deepEqual(parsePrefs(''), DEFAULT_PREFS);
});

test('damaged or hostile storage falls back to the defaults instead of throwing', () => {
  assert.deepEqual(parsePrefs('{not json'), DEFAULT_PREFS);
  assert.deepEqual(parsePrefs('[1,2]'), DEFAULT_PREFS);
  assert.deepEqual(parsePrefs('"hello"'), DEFAULT_PREFS);
});

test('a valid stored value is kept, and an unknown or wrongly-typed one is ignored field by field', () => {
  const got = parsePrefs(JSON.stringify({ textSize: 'large', haptics: false, defaultMode: 'plan', defaultModel: 42, bogus: 1, defaultEffort: 'high' }));
  assert.equal(got.textSize, 'large');
  assert.equal(got.haptics, false);
  assert.equal(got.defaultMode, 'plan');
  assert.equal(got.defaultModel, DEFAULT_PREFS.defaultModel); // 42 is not a model id
  assert.equal(got.defaultEffort, 'high');
  assert.equal('bogus' in got, false);
});

test('only known text sizes and permission modes are accepted', () => {
  assert.equal(parsePrefs(JSON.stringify({ textSize: 'huge' })).textSize, DEFAULT_PREFS.textSize);
  assert.equal(parsePrefs(JSON.stringify({ defaultMode: 'rm -rf' })).defaultMode, DEFAULT_PREFS.defaultMode);
});

test('every text size has a scale, with the default at 100%', () => {
  assert.equal(TEXT_SIZE_PERCENT.default, 100);
  assert.ok(TEXT_SIZE_PERCENT.small < 100 && TEXT_SIZE_PERCENT.large > 100);
});

test('theme, accent, motion and start tab are validated field by field', () => {
  const got = parsePrefs(JSON.stringify({ theme: 'light', accent: 'violet', reduceMotion: true, startTab: 'computers' }));
  assert.deepEqual([got.theme, got.accent, got.reduceMotion, got.startTab], ['light', 'violet', true, 'computers']);
  const bad = parsePrefs(JSON.stringify({ theme: 'neon', accent: 'plaid', reduceMotion: 'yes', startTab: 'settings' }));
  assert.deepEqual([bad.theme, bad.accent, bad.reduceMotion, bad.startTab], [DEFAULT_PREFS.theme, DEFAULT_PREFS.accent, DEFAULT_PREFS.reduceMotion, DEFAULT_PREFS.startTab]);
});
