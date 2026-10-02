import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { APP_PASSWORD, startApi, type ApiHarness } from './testHarness.js';

let h: ApiHarness;
afterEach(async () => {
  await h?.close();
});

describe('login brute-force protection', () => {
  it('locks out an address after repeated failures, even for the right password', async () => {
    h = await startApi({ maxLoginFailures: 3 });
    for (let i = 0; i < 3; i++) {
      const r = await h.call('POST', '/login', { password: 'wrong' }, { token: null });
      assert.equal(r.status, 401);
    }
    const locked = await h.call('POST', '/login', { password: APP_PASSWORD }, { token: null });
    assert.equal(locked.status, 429);
    assert.ok(Number(locked.headers.get('retry-after')) > 0);
  });

  it('a successful login resets the failure count', async () => {
    h = await startApi({ maxLoginFailures: 3 });
    await h.call('POST', '/login', { password: 'wrong' }, { token: null });
    await h.call('POST', '/login', { password: 'wrong' }, { token: null });
    assert.equal((await h.call('POST', '/login', { password: APP_PASSWORD }, { token: null })).status, 200);
    await h.call('POST', '/login', { password: 'wrong' }, { token: null });
    await h.call('POST', '/login', { password: 'wrong' }, { token: null });
    assert.equal((await h.call('POST', '/login', { password: APP_PASSWORD }, { token: null })).status, 200);
  });

  it('rejects a missing or non-string password without issuing a token', async () => {
    h = await startApi();
    for (const body of [{}, { password: null }, { password: ['x'] }, { password: { a: 1 } }]) {
      const r = await h.call('POST', '/login', body, { token: null });
      assert.equal(r.status, 401);
      assert.equal(r.body.token, undefined);
    }
  });

  it('keys by X-Forwarded-For only when the proxy is trusted', async () => {
    h = await startApi({ maxLoginFailures: 2, trustProxy: true });
    for (let i = 0; i < 2; i++) await h.call('POST', '/login', { password: 'x' }, { token: null, headers: { 'x-forwarded-for': '203.0.113.9' } });
    const blocked = await h.call('POST', '/login', { password: APP_PASSWORD }, { token: null, headers: { 'x-forwarded-for': '203.0.113.9' } });
    const otherClient = await h.call('POST', '/login', { password: APP_PASSWORD }, { token: null, headers: { 'x-forwarded-for': '198.51.100.7' } });
    assert.equal(blocked.status, 429);
    assert.equal(otherClient.status, 200);
  });
});

describe('request size limits', () => {
  it('rejects large bodies before authentication', async () => {
    h = await startApi();
    const big = JSON.stringify({ password: 'x'.repeat(200_000) });
    const r = await h.call('POST', '/login', undefined, { token: null, raw: big });
    assert.equal(r.status, 413);
  });

  it('unauthenticated requests never reach the large-body parser', async () => {
    h = await startApi();
    const big = JSON.stringify({ text: 'x'.repeat(2_000_000) });
    const r = await h.call('POST', '/vms/v/sessions', undefined, { token: null, raw: big });
    assert.equal(r.status, 401);
  });
});

describe('security headers', () => {
  it('forbids framing of API responses', async () => {
    h = await startApi();
    const r = await h.call('GET', '/vms');
    assert.equal(r.headers.get('x-frame-options'), 'DENY');
  });
});

describe('input validation', () => {
  it('new session: rejects images as a string, object text, and bad types', async () => {
    h = await startApi();
    for (const body of [{ images: 'abc' }, { text: { a: 1 } }, { text: 'hi', cwd: 5 }, { text: 'hi', images: [{ mediaType: 'text/html', dataBase64: 'AA' }] }]) {
      const r = await h.call('POST', '/vms/vm1/sessions', body);
      assert.equal(r.status, 400, JSON.stringify(body));
    }
    assert.deepEqual(h.sent, []);
  });

  it('follow-up message: same validation', async () => {
    h = await startApi();
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/messages', { images: 'abc' })).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/messages', { text: ['x'] })).status, 400);
  });

  it('permission-mode must be one of the enum values', async () => {
    h = await startApi();
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/permission-mode', { mode: 'rm -rf /' })).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/permission-mode', {})).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/permission-mode', { mode: 'plan' })).status, 202);
  });

  it('model and effort are validated', async () => {
    h = await startApi();
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/model', { model: { a: 1 } })).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/effort', { effort: 'extreme' })).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/effort', { effort: 'high' })).status, 202);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/effort', { effort: null })).status, 202);
  });
});

describe('delivery ordering', () => {
  it('does not store or broadcast ghost messages when the VM is not connected', async () => {
    h = await startApi();
    h.state.connected = false;
    const created = await h.call('POST', '/vms/vm1/sessions', { text: 'hello' });
    assert.equal(created.status, 503);
    const followup = await h.call('POST', '/vms/vm1/sessions/s1/messages', { text: 'hello' });
    assert.equal(followup.status, 503);
    assert.deepEqual(h.broadcasts, []);
    assert.deepEqual(h.db.listMessages('s1', 'vm1'), []);
  });

  it('stores and broadcasts when the VM is connected', async () => {
    h = await startApi();
    const r = await h.call('POST', '/vms/vm1/sessions/s1/messages', { text: 'hello' });
    assert.equal(r.status, 202);
    assert.equal(h.sent.length, 1);
    assert.equal(h.db.listMessages('s1', 'vm1').length, 1);
  });
});

describe('permission-response', () => {
  it('does not announce "resolved" when delivery failed', async () => {
    h = await startApi();
    h.state.connected = false;
    const r = await h.call('POST', '/vms/vm1/sessions/s1/permission-response', { requestId: 'r1', behavior: 'allow' });
    assert.equal(r.status, 503);
    assert.deepEqual(h.broadcasts, []);
  });

  it('announces resolved after successful delivery', async () => {
    h = await startApi();
    const r = await h.call('POST', '/vms/vm1/sessions/s1/permission-response', { requestId: 'r1', behavior: 'deny', message: 'no' });
    assert.equal(r.status, 202);
    assert.deepEqual(h.broadcasts.map((b) => b.type), ['permission_resolved']);
  });

  it('rejects an invalid behavior or missing requestId', async () => {
    h = await startApi();
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/permission-response', { requestId: 'r1', behavior: 'yes' })).status, 400);
    assert.equal((await h.call('POST', '/vms/vm1/sessions/s1/permission-response', { behavior: 'allow' })).status, 400);
    assert.deepEqual(h.sent, []);
  });
});

describe('MCP server registration', () => {
  it('rejects SSRF targets', async () => {
    h = await startApi();
    for (const url of ['http://169.254.169.254/latest', 'http://localhost:9/', 'http://10.0.0.1/', 'file:///etc/passwd', 'https://u:p@example.com/']) {
      const r = await h.call('POST', '/mcp/escanor', { url, token: 't' });
      assert.equal(r.status, 400, url);
    }
    assert.deepEqual(h.db.listMcpServers(), []);
  });

  it('accepts a public https URL and, with the opt-in, a private one — but never metadata', async () => {
    h = await startApi();
    assert.equal((await h.call('POST', '/mcp/escanor', { url: 'https://mcp.example.com/mcp', token: 't' })).status, 200);
    await h.close();
    h = await startApi({ allowPrivateMcp: true });
    assert.equal((await h.call('POST', '/mcp/escanor', { url: 'http://localhost:8000/mcp', token: 't' })).status, 200);
    assert.equal((await h.call('POST', '/mcp/escanor', { url: 'http://169.254.169.254/', token: 't' })).status, 400);
  });
});

describe('message history', () => {
  it('returns only the most recent `limit` messages, oldest first, scoped to the VM', async () => {
    h = await startApi();
    for (let i = 0; i < 5; i++) h.db.insertMessage({ sessionId: 's1', vmId: 'vm1', message: { i } });
    h.db.insertMessage({ sessionId: 's1', vmId: 'other-vm', message: { leak: true } });
    const r = await h.call('GET', '/vms/vm1/sessions/s1/messages?limit=2');
    assert.deepEqual(r.body.map((m: any) => m.message), [{ i: 3 }, { i: 4 }]);
    const all = await h.call('GET', '/vms/vm1/sessions/s1/messages');
    assert.equal(all.body.length, 5);
    assert.ok(all.body.every((m: any) => m.vmId === 'vm1'));
  });
});
