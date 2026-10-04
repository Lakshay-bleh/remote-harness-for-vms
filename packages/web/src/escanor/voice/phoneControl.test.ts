import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { controlStep } from './phoneControl';

describe('controlStep', () => {
  it('waits for the phone to answer', () => {
    assert.equal(controlStep(null, true), 'checking');
  });
  it('is done once the person switched it on', () => {
    assert.equal(controlStep({ enabled: true, available: true, restricted: true }, false), 'on');
  });
  it('says when this download has no phone control', () => {
    assert.equal(controlStep({ enabled: false, available: false }, true), 'notInBuild');
  });
  it('asks for agreement before anything else', () => {
    assert.equal(controlStep({ enabled: false, available: true, restricted: true }, false), 'disclosure');
    assert.equal(controlStep({ enabled: false, available: true, restricted: false }, false), 'disclosure');
  });
  it('unlocks the restricted setting before sending them to Accessibility', () => {
    assert.equal(controlStep({ enabled: false, available: true, restricted: true }, true), 'restricted');
  });
  it('goes to Accessibility when nothing is restricted, or Android does not say', () => {
    assert.equal(controlStep({ enabled: false, available: true, restricted: false }, true), 'turnOn');
    assert.equal(controlStep({ enabled: false, available: true, restricted: null }, true), 'turnOn');
    assert.equal(controlStep({ enabled: false }, true), 'turnOn');
  });
});
