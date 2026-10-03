import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { describeDue, isFinished, OPTIONAL_CONSENTS, REQUEST_TYPES, requestProblem, statusLabel } from './privacy';
import { daysUntil, DELETION_FACTS, emailConfirmed, parseCodeInput } from './security';

describe('privacy', () => {
  it('keeps the website’s four optional consents and its request types', () => {
    assert.deepEqual(OPTIONAL_CONSENTS.map((c) => c.purpose), ['marketing', 'product_updates', 'analytics', 'ai_improvement']);
    assert.deepEqual(REQUEST_TYPES.map((r) => r.value).sort(), ['access', 'consent_withdrawal', 'correction', 'erasure', 'grievance', 'nomination']);
  });
  it('describes deadlines in days and hours, before and after they pass', () => {
    const now = new Date('2026-10-03T12:00:00Z');
    assert.equal(describeDue('2026-10-05T13:00:00Z', now), 'due in 2 days');
    assert.equal(describeDue('2026-10-03T17:00:00Z', now), 'due in 5 hours');
    assert.equal(describeDue('2026-10-03T12:20:00Z', now), 'due in 1 hour');
    assert.equal(describeDue('2026-10-02T11:00:00Z', now), 'overdue by 1 day');
    assert.equal(describeDue('garbage', now), '');
  });
  it('labels statuses and knows when one is finished', () => {
    assert.equal(statusLabel('fulfilled'), 'Completed');
    assert.equal(statusLabel('rejected'), 'Declined');
    assert.equal(statusLabel('something_new'), 'something_new');
    assert.equal(isFinished('fulfilled') && isFinished('rejected'), true);
    assert.equal(isFinished('in_progress'), false);
  });
  it('checks a request against the server’s limits before sending', () => {
    const ok = { request_type: 'access' as const, subject: 'My data', details: '' };
    assert.equal(requestProblem(ok), null);
    assert.match(requestProblem({ ...ok, subject: ' a ' })!, /at least 3/);
    assert.match(requestProblem({ ...ok, subject: 'x'.repeat(201) })!, /shorter/);
    assert.match(requestProblem({ ...ok, details: 'x'.repeat(5001) })!, /too long/);
  });
});

describe('security', () => {
  it('reads a six-digit code or a backup code, however it was typed, and nothing else', () => {
    assert.equal(parseCodeInput('123 456'), '123456');
    assert.equal(parseCodeInput(' 123456 '), '123456');
    assert.equal(parseCodeInput('abcd-efgh'), 'ABCD-EFGH');
    assert.equal(parseCodeInput('abcd efgh'), 'ABCD-EFGH');
    for (const bad of ['', '12345', '1234567', 'ABCD', 'ABCD-EFG0', 'ABC1-EFGH']) assert.equal(parseCodeInput(bad), null, bad); // 0 and 1 are never in a backup code
  });
  it('confirms the email without fuss about case or spaces, and never when there is none', () => {
    assert.equal(emailConfirmed(' A@Example.com ', 'a@example.com'), true);
    assert.equal(emailConfirmed('b@example.com', 'a@example.com'), false);
    assert.equal(emailConfirmed('', ''), false);
    assert.equal(emailConfirmed('x', undefined), false);
  });
  it('says how long until a date', () => {
    const now = new Date('2026-10-03T12:00:00Z');
    assert.equal(daysUntil('2026-10-10T11:00:00Z', now), 'in 6 days');
    assert.equal(daysUntil('2026-10-04T12:30:00Z', now), 'in 1 day');
    assert.equal(daysUntil('2026-10-03T16:00:00Z', now), 'in 4 hours');
    assert.equal(daysUntil('2026-10-02T00:00:00Z', now), 'now');
  });
  it('tells the person what deletion does and keeps', () => {
    assert.equal(DELETION_FACTS.length, 4);
    assert.ok(DELETION_FACTS.some((f) => /cancel the deletion/.test(f)) && DELETION_FACTS.some((f) => /kept/.test(f)));
  });
});

import { exportFileName, exportText, sizeLabel } from './dataExport';
describe('data export', () => {
  it('names the file by date, and writes readable JSON', () => {
    assert.equal(exportFileName(new Date('2026-10-03T23:59:00Z')), 'escanor-my-data-2026-10-03.json');
    assert.equal(exportText({ a: 1 }), '{\n  "a": 1\n}');
  });
  it('says how big it is', () => {
    assert.equal(sizeLabel('x'.repeat(500)), '500 bytes');
    assert.equal(sizeLabel('x'.repeat(2048)), '2.0 KB');
    assert.equal(sizeLabel('x'.repeat(50 * 1024)), '50 KB');
    assert.equal(sizeLabel('é'.repeat(10)), '20 bytes'); // bytes, not characters
  });
});
