import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assistantReach } from './reach';

const item = (over: Record<string, unknown>) => ({ provider_id: 'x', name: 'X', connected: true, auth_method: 'oauth', available_to_assistant: true, needs_reconnect: false, ...over }) as never;

test('connected services whose reach could not be checked count, so 25 connected never reads as nothing', () => {
  const many = Array.from({ length: 25 }, (_, i) => item({ provider_id: `p${i}`, available_to_assistant: null }));
  const r = assistantReach(many);
  assert.equal(r.usable.length, 25);
  assert.equal(r.invite, false);
});

test('ones without assistant tools or needing reconnect are not usable, but are not "nothing connected" either', () => {
  const r = assistantReach([item({ available_to_assistant: false }), item({ available_to_assistant: null, needs_reconnect: true })]);
  assert.equal(r.usable.length, 0);
  assert.equal(r.invite, false);
});

test('invites connecting a service only when nothing is connected, and not while unknown', () => {
  assert.equal(assistantReach([]).invite, true);
  assert.equal(assistantReach(undefined).invite, false);
});
