import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { replyOf } from './computerChat';

describe('what the computer said back', () => {
  it('keeps whether it is waiting for an answer, not only its words', () => {
    assert.deepEqual(replyOf([{ t: 'reply', id: 'x', reply: 'Delete them? Say yes or no.', listenAgain: true }]), { reply: 'Delete them? Say yes or no.', listenAgain: true });
    assert.deepEqual(replyOf([{ t: 'reply', id: 'x', reply: 'Done.', listenAgain: false }]), { reply: 'Done.', listenAgain: false });
    assert.deepEqual(replyOf([]), { reply: '' });
  });

  it('throws the computer’s own error, so it can be explained', () => {
    assert.throws(() => replyOf([{ t: 'error', id: 'x', message: 'Not allowed from phones.' }]), /Not allowed from phones/);
  });
});
