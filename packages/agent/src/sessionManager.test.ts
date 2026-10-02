import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SessionManager } from './sessionManager.js';

describe('SessionManager', () => {
  it('reports an error for an unknown session id instead of silently starting a fresh conversation', () => {
    const sent: any[] = [];
    const dir = mkdtempSync(join(tmpdir(), 'sm-test-'));
    const m = new SessionManager(dir, dir, [{ id: 'default', label: 'default' }], (msg) => sent.push(msg));
    m.handleUserInput({ type: 'user_input', sessionId: 'not-a-known-session', text: 'hi' });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].type, 'error');
    assert.equal(sent[0].sessionId, 'not-a-known-session');
    assert.match(sent[0].message, /unknown session/i);
    assert.deepEqual(m.summaries(), []);
  });
});
