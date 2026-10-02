import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { deriveKey, seal, open, isSealed } from './secretbox.js';

describe('secretbox', () => {
  const key = deriveKey('a-long-random-secret-for-tests-0123456789');

  it('round-trips and never contains the plaintext', () => {
    const boxed = seal(key, 'esc_mcp_token_value');
    assert.equal(isSealed(boxed), true);
    assert.equal(boxed.includes('esc_mcp_token_value'), false);
    assert.equal(open(key, boxed), 'esc_mcp_token_value');
  });

  it('uses a fresh nonce each time', () => {
    assert.notEqual(seal(key, 'same'), seal(key, 'same'));
  });

  it('rejects tampered ciphertext and the wrong key', () => {
    const boxed = seal(key, 'value');
    const parts = boxed.split(':');
    parts[4] = Buffer.from('tampered').toString('base64');
    assert.throws(() => open(key, parts.join(':')));
    assert.throws(() => open(deriveKey('another-secret-entirely-0123456789ab'), boxed));
  });

  it('only treats the versioned format as sealed', () => {
    assert.equal(isSealed('plain-token'), false);
    assert.equal(isSealed('enc:v1:a:b:c'), true);
  });
});
