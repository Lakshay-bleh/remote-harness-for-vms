import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { BackStack } from './back';

describe('BackStack', () => {
  it('sends back to the most recently opened thing, then the one under it', () => {
    const s = new BackStack();
    const log: string[] = [];
    s.push(() => log.push('page'));
    s.push(() => log.push('sheet'));
    assert.equal(s.press(), true);
    assert.deepEqual(log, ['sheet']);
  });

  it('removes an entry when its screen goes away, wherever it sits in the stack', () => {
    const s = new BackStack();
    const log: string[] = [];
    const page = () => log.push('page');
    const sheet = () => log.push('sheet');
    s.push(page);
    s.push(sheet);
    s.remove(page); // the page closed underneath the sheet
    s.press();
    assert.deepEqual(log, ['sheet']);
    s.remove(sheet);
    assert.equal(s.press(), false); // nothing left: the caller decides (leave the app)
  });

  it('ignores removing something that was never added', () => {
    const s = new BackStack();
    s.remove(() => undefined);
    assert.equal(s.press(), false);
  });

  it('a lower-priority fallback (the shell going back to the Chat tab) never beats something opened inside a screen', () => {
    const s = new BackStack();
    const log: string[] = [];
    const shell = () => log.push('shell');
    const sheet = () => log.push('sheet');
    s.push(sheet); // a child registered first, as React runs child effects before the parent's
    s.push(shell, 0);
    s.press();
    assert.deepEqual(log, ['sheet']);
    s.remove(sheet);
    s.press();
    assert.deepEqual(log, ['sheet', 'shell']);
  });
});
