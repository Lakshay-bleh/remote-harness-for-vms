import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { refreshOutcome } from './client';

describe('refreshOutcome', () => {
  it('ends the session only when the server refuses the refresh token itself', () => {
    for (const s of [400, 401, 403]) assert.equal(refreshOutcome(s), 'rejected', String(s));
  });
  it('never signs anyone out because the server was busy, down or limiting requests', () => {
    for (const s of [404, 408, 429, 500, 502, 503, 504]) assert.equal(refreshOutcome(s), 'unavailable', String(s));
  });
});
