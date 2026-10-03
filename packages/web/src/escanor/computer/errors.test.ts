import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { explainFailure } from './errors';

describe('explainFailure: every error says what happened and WHERE to change it', () => {
  it('a permission switched off for phones names the setting, the place on the computer, and offers to ask', () => {
    const msg = '“Open apps and websites” is turned off for phones. On your computer, open Escanor Desktop, go to Settings, then Permissions, and switch it on in the Phone column.';
    const e = explainFailure(msg);
    assert.equal(e.where, 'computer');
    assert.match(e.title, /Open apps and websites/);
    assert.ok(e.steps.some((s) => /Escanor Desktop/.test(s) && /Permissions/.test(s)));
    assert.deepEqual(e.ask, { groupLabel: 'Open apps and websites' });
  });

  it('a computer that did not answer is a computer-side problem with its checklist', () => {
    const e = explainFailure('The computer did not answer. Is it on and online?');
    assert.equal(e.where, 'computer');
    assert.ok(e.steps.join(' ').match(/open/i));
    assert.ok(e.steps.join(' ').match(/Away from home/));
  });

  it('a dead sign-in is a this-app problem', () => {
    const e = explainFailure('Your Escanor session ended. Please sign in again.');
    assert.equal(e.where, 'phone');
    assert.ok(e.steps.join(' ').match(/Settings|sign in/i));
  });

  it('a phone the computer no longer knows must be paired again, on both sides', () => {
    const e = explainFailure('Not allowed.');
    assert.equal(e.where, 'both');
    assert.ok(e.steps.join(' ').match(/Pair a phone/));
  });

  it('an old desktop is told to update the desktop', () => {
    const e = explainFailure('This computer’s Escanor Desktop is too old for that. Update Escanor Desktop on the computer, then try again.');
    assert.equal(e.where, 'computer');
    assert.match(e.steps.join(' '), /Update Escanor Desktop/);
  });

  it('anything unknown still says something useful and never shows a blank', () => {
    for (const raw of ['', 'boom', undefined, null, new Error('weird thing')]) {
      const e = explainFailure(raw as never);
      assert.ok(e.title.length > 0);
      assert.ok(['phone', 'computer', 'both'].includes(e.where));
    }
  });
});
