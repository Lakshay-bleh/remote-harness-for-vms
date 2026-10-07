import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { MessageDto } from '@remote-harness/shared';
import { busySince, SESSION_ENDED } from './groupMessages';

let n = 0;
const row = (message: unknown, createdAt = '2026-10-07T10:00:00Z'): MessageDto => ({ id: ++n, sessionId: 's', vmId: 'v', message, createdAt });
const asked = row({ type: 'user', local: true, message: { content: 'fix it' } });

describe('busySince', () => {
  it('is busy from the prompt until the turn ends with a result', () => {
    assert.equal(busySince([asked]), Date.parse('2026-10-07T10:00:00Z'));
    assert.equal(busySince([asked, row({ type: 'assistant', message: { content: [] } })]), Date.parse('2026-10-07T10:00:00Z'));
    assert.equal(busySince([asked, row({ type: 'result' })]), null);
  });

  it('treats a stored error, or the session ending, as the end of the run', () => {
    assert.equal(busySince([asked, row({ type: 'error', message: 'boom' })]), null);
    assert.equal(busySince([asked, row({ type: SESSION_ENDED })]), null);
  });

  it('a new prompt after an error is busy again', () => {
    assert.notEqual(busySince([asked, row({ type: 'error', message: 'boom' }), row({ type: 'user', local: true }, '2026-10-07T10:05:00Z')]), null);
  });
});
