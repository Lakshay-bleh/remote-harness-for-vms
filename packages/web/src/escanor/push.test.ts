import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { routeFor, stateFromPermission } from './push';

describe('routeFor (where tapping a notification goes)', () => {
  it('sends each kind to the place that deals with it', () => {
    assert.equal(routeFor({ kind: 'deployment_approvals' }), 'assistant');
    assert.equal(routeFor({ kind: 'emergency_alerts' }), 'assistant');
    assert.equal(routeFor({ kind: 'team_pings' }), 'assistant');
    assert.equal(routeFor({ kind: 'server_down' }), 'machines');
  });

  it('falls back to the main screen for anything it does not know, however odd', () => {
    for (const odd of [undefined, null, 5, 'x', {}, { kind: 42 }, { kind: 'nonsense' }, { kind: '__proto__' }, { kind: 'constructor' }]) assert.equal(routeFor(odd), 'assistant', JSON.stringify(odd));
  });
});

describe('stateFromPermission', () => {
  it('reads the phone’s answer', () => {
    assert.equal(stateFromPermission('granted'), 'on');
    assert.equal(stateFromPermission('denied'), 'denied');
    assert.equal(stateFromPermission('prompt'), 'off');
    assert.equal(stateFromPermission('prompt-with-rationale'), 'off');
    assert.equal(stateFromPermission('something new'), 'off');
  });
});

import { channelState } from './push';

describe('channelState (is the Alerts channel able to show anything?)', () => {
  const ch = (importance: number, id = 'escanor_alerts') => ({ id, importance });
  it('is fine at default importance or above', () => {
    for (const i of [3, 4, 5]) assert.equal(channelState([ch(i)]), 'ok', String(i));
  });
  it('says blocked when the person switched the channel off', () => {
    assert.equal(channelState([ch(0)]), 'blocked');
  });
  it('says quiet when it can only appear silently', () => {
    for (const i of [1, 2]) assert.equal(channelState([ch(i)]), 'quiet', String(i));
  });
  it('says missing when the channel was never created, and ignores other channels', () => {
    assert.equal(channelState([]), 'missing');
    assert.equal(channelState([ch(4, 'something_else')]), 'missing');
    assert.equal(channelState(undefined), 'missing');
  });
});
