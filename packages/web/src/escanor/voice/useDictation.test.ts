import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { joinSpoken } from './useDictation';

describe('joinSpoken', () => {
  it('adds what was heard after what was typed, with one space', () => {
    assert.equal(joinSpoken('open the', 'pod bay doors'), 'open the pod bay doors');
    assert.equal(joinSpoken('trailing   ', 'words'), 'trailing words');
  });
  it('is just the speech when nothing was typed, and just the text when nothing was heard', () => {
    assert.equal(joinSpoken('', 'hello'), 'hello');
    assert.equal(joinSpoken('typed', ''), 'typed');
    assert.equal(joinSpoken('', ''), '');
  });
});
