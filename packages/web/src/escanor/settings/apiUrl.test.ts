import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkApiUrl } from './apiUrl';

describe('checkApiUrl', () => {
  it('accepts an https server and adds the API path when it is missing', () => {
    assert.deepEqual(checkApiUrl('https://api.example.com'), { ok: true, url: 'https://api.example.com/api/v1' });
    assert.deepEqual(checkApiUrl(' https://api.example.com/ '), { ok: true, url: 'https://api.example.com/api/v1' });
    assert.deepEqual(checkApiUrl('https://api.example.com/api/v1/'), { ok: true, url: 'https://api.example.com/api/v1' });
  });

  it('allows plain http only for this device and the Android emulator', () => {
    for (const host of ['localhost:8000', '127.0.0.1:8000', '10.0.2.2:8000']) assert.equal(checkApiUrl(`http://${host}`).ok, true, host);
    for (const host of ['api.example.com', '192.168.1.5:8000', '8.8.8.8']) {
      const r = checkApiUrl(`http://${host}`);
      assert.equal(r.ok, false, host);
      assert.match((r as { reason: string }).reason, /https/);
    }
  });

  it('refuses things that are not a plain server address', () => {
    for (const bad of ['', 'api.example.com', 'ftp://x.com', 'javascript:alert(1)', 'https://user:pw@api.example.com', 'https://api.example.com/?a=1', 'https://api.example.com/#x', 'https://', 'https://a b.com']) {
      assert.equal(checkApiUrl(bad).ok, false, bad);
    }
  });

  it('does not let a look-alike host pass as the local one', () => {
    for (const bad of ['http://localhost.evil.com', 'http://127.0.0.1.evil.com', 'http://evil.com@localhost']) assert.equal(checkApiUrl(bad).ok, false, bad);
  });
});
