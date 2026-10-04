import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { outsideApp, wakeStep, type WakeStatus } from './wakeWord';

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

describe('outsideApp', () => {
  it('opens straight away when the phone allows drawing over other apps', () => {
    const o = outsideApp(s({ overlayAllowed: true, fullScreenAllowed: true }));
    assert.equal(o.best, true);
    assert.equal(o.canAllowOverlay, false);
  });
  it('falls back to a notification, and says what to allow to do better', () => {
    const o = outsideApp(s({ overlayAllowed: false, fullScreenAllowed: false }));
    assert.equal(o.best, false);
    assert.equal(o.canAllowOverlay, true);
    assert.equal(o.canAllowFullScreen, true);
    assert.match(o.line, /Full-screen notifications/);
  });
  it('treats an older app that does not report it as needing the overlay, not as broken', () => {
    const o = outsideApp(s());
    assert.equal(o.canAllowOverlay, true);
    assert.equal(o.canAllowFullScreen, false);
  });
});
