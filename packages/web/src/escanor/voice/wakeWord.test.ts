import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { wakeStep, type WakeStatus } from './wakeWord';

const s = (over: Partial<WakeStatus> = {}): WakeStatus => ({ running: false, modelReady: true, downloading: false, micAllowed: true, ...over });

describe('wakeStep', () => {
  it('says "Hey Escanor" is for the Android app only, outside it', () => {
    assert.equal(wakeStep(s(), false), 'unsupported');
    assert.equal(wakeStep(null, true), 'unsupported');
  });
  it('walks through what is in the way, in order: model, then microphone, then ready', () => {
    assert.equal(wakeStep(s({ modelReady: false, micAllowed: false }), true), 'download');
    assert.equal(wakeStep(s({ micAllowed: false }), true), 'microphone');
    assert.equal(wakeStep(s(), true), 'ready');
  });
  it('is listening once it is running', () => assert.equal(wakeStep(s({ running: true }), true), 'listening'));
});
