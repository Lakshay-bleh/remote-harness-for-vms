import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseAgentFrame,
  parseUserInput,
  parseNewSession,
  isPermissionMode,
  isEffortLevel,
  isPermissionBehavior,
  safeEqual,
  RateLimiter,
  clampLimit,
  isWeakSecret,
} from '../src/validate.ts';
import { validateMcpUrl } from '../src/protocol.ts';

describe('parseAgentFrame', () => {
  it('accepts well-formed frames', () => {
    const f = { type: 'sdk_message', sessionId: 's', message: {} };
    assert.deepEqual(parseAgentFrame(JSON.stringify(f)), f);
  });
  it('rejects non-objects, unknown types and missing fields', () => {
    for (const raw of ['null', '1', '"x"', '[]', '{', '{"type":"hello"}', '{"type":"nope"}', '{"type":"sdk_message"}']) {
      assert.equal(parseAgentFrame(raw), null, raw);
    }
  });
  it('rejects oversized identifiers', () => {
    assert.equal(parseAgentFrame(JSON.stringify({ type: 'hello', vmName: 'x'.repeat(300), accounts: [], sessions: [] })), null);
  });
});

describe('parseUserInput', () => {
  it('accepts text only, images only, and both', () => {
    assert.deepEqual(parseUserInput({ text: 'hi' }), { ok: true, value: { text: 'hi', images: undefined } });
    const img = { mediaType: 'image/png', dataBase64: 'AAAA' };
    assert.deepEqual(parseUserInput({ images: [img] }), { ok: true, value: { text: '', images: [img] } });
  });
  it('rejects empty input', () => {
    assert.equal(parseUserInput({}).ok, false);
    assert.equal(parseUserInput(undefined).ok, false);
    assert.equal(parseUserInput({ text: '', images: [] }).ok, false);
  });
  it('rejects a string for images (would iterate characters) and object text', () => {
    assert.equal(parseUserInput({ images: 'abc' }).ok, false);
    assert.equal(parseUserInput({ text: { a: 1 } }).ok, false);
  });
  it('rejects malformed images, non-image media types, and too many images', () => {
    assert.equal(parseUserInput({ images: [{ mediaType: 'text/html', dataBase64: 'AAAA' }] }).ok, false);
    assert.equal(parseUserInput({ images: [{ mediaType: 'image/png' }] }).ok, false);
    assert.equal(parseUserInput({ images: [null] }).ok, false);
    const img = { mediaType: 'image/png', dataBase64: 'AAAA' };
    assert.equal(parseUserInput({ images: Array(11).fill(img) }).ok, false);
  });
});

describe('parseNewSession', () => {
  it('validates optional cwd/accountId types', () => {
    assert.equal(parseNewSession({ text: 'hi', cwd: 5 }).ok, false);
    assert.equal(parseNewSession({ text: 'hi', accountId: {} }).ok, false);
    const r = parseNewSession({ text: 'hi', cwd: 'app', accountId: 'a' });
    assert.deepEqual(r.ok && r.value, { text: 'hi', images: undefined, cwd: 'app', accountId: 'a' });
  });
});

describe('enums', () => {
  it('permission mode / effort / behavior', () => {
    assert.equal(isPermissionMode('default'), true);
    assert.equal(isPermissionMode('bypassPermissions'), true);
    assert.equal(isPermissionMode('rm -rf'), false);
    assert.equal(isPermissionMode(undefined), false);
    assert.equal(isEffortLevel('max'), true);
    assert.equal(isEffortLevel('extreme'), false);
    assert.equal(isPermissionBehavior('allow'), true);
    assert.equal(isPermissionBehavior('yes'), false);
  });
});

describe('safeEqual', () => {
  it('compares strings and fails closed on non-strings', () => {
    assert.equal(safeEqual('abc', 'abc'), true);
    assert.equal(safeEqual('abc', 'abd'), false);
    assert.equal(safeEqual('abc', 'abcd'), false);
    assert.equal(safeEqual(undefined, undefined), false);
    assert.equal(safeEqual(undefined, 'undefined'), false);
    assert.equal(safeEqual('', ''), false); // an empty secret must never match
  });
});

describe('validateMcpUrl', () => {
  it('accepts public https', () => {
    assert.equal(validateMcpUrl('https://mcp.escanor.in/mcp').ok, true);
  });
  it('rejects non-http(s), credentials in URL, and garbage', () => {
    for (const u of ['ftp://x.com', 'file:///etc/passwd', 'javascript:alert(1)', 'https://user:pw@x.com', 'not a url', '', 5]) {
      assert.equal(validateMcpUrl(u as string).ok, false, String(u));
    }
  });
  it('always rejects cloud metadata / link-local targets', () => {
    for (const u of ['http://169.254.169.254/latest/meta-data', 'http://[fd00:ec2::254]/', 'http://metadata.google.internal/', 'http://169.254.1.1/']) {
      assert.equal(validateMcpUrl(u, { allowPrivate: true }).ok, false, u);
    }
  });
  it('rejects loopback and private ranges unless allowPrivate', () => {
    for (const u of ['http://localhost:8000/', 'http://127.0.0.1/', 'http://10.0.0.5/', 'http://192.168.1.2/', 'http://172.16.0.1/', 'http://[::1]/', 'http://0.0.0.0/', 'http://2130706433/']) {
      assert.equal(validateMcpUrl(u).ok, false, u);
      if (!u.includes('2130706433')) assert.equal(validateMcpUrl(u, { allowPrivate: true }).ok, true, u);
    }
  });
});

describe('RateLimiter', () => {
  it('blocks a key after max failures within the window and resets on success', () => {
    let now = 0;
    const rl = new RateLimiter({ maxFailures: 3, windowMs: 1000, now: () => now });
    assert.equal(rl.blocked('k'), false);
    rl.fail('k'); rl.fail('k');
    assert.equal(rl.blocked('k'), false);
    rl.fail('k');
    assert.equal(rl.blocked('k'), true);
    assert.equal(rl.blocked('other'), false);
    now = 1001;
    assert.equal(rl.blocked('k'), false);
    rl.fail('k'); rl.fail('k'); rl.fail('k');
    assert.equal(rl.blocked('k'), true);
    rl.succeed('k');
    assert.equal(rl.blocked('k'), false);
  });
  it('bounds memory', () => {
    const rl = new RateLimiter({ maxFailures: 1, windowMs: 10_000, maxKeys: 5 });
    for (let i = 0; i < 50; i++) rl.fail(`k${i}`);
    assert.ok(rl.size() <= 5);
  });
});

describe('clampLimit', () => {
  it('parses and bounds', () => {
    assert.equal(clampLimit(undefined, 100, 1000), 100);
    assert.equal(clampLimit('50', 100, 1000), 50);
    assert.equal(clampLimit('99999', 100, 1000), 1000);
    assert.equal(clampLimit('-3', 100, 1000), 100);
    assert.equal(clampLimit('abc', 100, 1000), 100);
  });
});

describe('isWeakSecret', () => {
  it('rejects short, placeholder and low-variety secrets', () => {
    for (const v of [undefined, '', 'short', 'change-me', 'change-me-change-me-change-me', 'CHANGEME-aaaaaaaaaaaaaaaaaaaaaaa', 'a'.repeat(40), 'replace-with-a-random-secret-xx']) {
      assert.equal(isWeakSecret(v), true, String(v));
    }
  });
  it('accepts a long random-looking secret', () => {
    assert.equal(isWeakSecret('b7f3c1e09a4d4e6f8a21c5d97e30b1aa'), false);
  });
});

import { redactSecrets } from '../src/validate.ts';

describe('redactSecrets', () => {
  const R = '[REDACTED]';
  it('masks well-known credential formats inside strings', () => {
    // Built at runtime so no token-shaped literal sits in source (GitHub push protection would flag them).
    const j = (...p: string[]) => p.join('');
    const aws = j('AKIA', 'IOSFODNN7', 'EXAMPLE');
    const cases: Record<string, string> = {
      anthropic: j('key sk-', 'ant-api03-', 'abcdefghijklmnopqrstuvwxyz0123456789'),
      aws,
      github: j('gh', 'p_', 'abcdefghijklmnopqrstuvwxyz0123456789'),
      githubPat: j('github_', 'pat_11ABCDEFG0', 'abcdefghijklmnopqrstuvwxyz'),
      slack: j('xo', 'xb-1234567890-', 'abcdefghijklmnop'),
      bearer: 'curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"',
      jwt: j('ey', 'JhbGciOiJIUzI1NiJ9.', 'ey', 'JzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnopqrstuvwxyz'),
      pem: j('-----BEGIN RSA PRIVATE', ' KEY-----\nMIIEow...\n-----END RSA PRIVATE', ' KEY-----'),
    };
    for (const [name, text] of Object.entries(cases)) {
      const out = redactSecrets(text) as string;
      assert.ok(out.includes(R), name);
      assert.equal(/sk-ant-api03|AKIAIOSFODNN7|ghp_abc|github_pat_11|xoxb-1234|abcdefghijklmnopqrstuvwxyz012345|MIIEow/.test(out), false, name);
    }
  });

  it('masks values under sensitive keys at any depth, leaves the rest intact', () => {
    const out = redactSecrets({
      type: 'permission_request',
      input: { command: 'ls', headers: { Authorization: 'Bearer x', 'X-Api-Key': 'abc' }, nested: [{ password: 'hunter2', note: 'ok' }] },
    }) as any;
    assert.equal(out.input.command, 'ls');
    assert.equal(out.input.headers.Authorization, R);
    assert.equal(out.input.headers['X-Api-Key'], R);
    assert.equal(out.input.nested[0].password, R);
    assert.equal(out.input.nested[0].note, 'ok');
  });

  it('does not touch ordinary text, numbers, null, or mutate its input', () => {
    const input = { a: 'hello world', b: 5, c: null, d: ['x'], token: 'secret-value' };
    const snapshot = JSON.stringify(input);
    const out = redactSecrets(input) as any;
    assert.equal(JSON.stringify(input), snapshot);
    assert.equal(out.a, 'hello world');
    assert.equal(out.b, 5);
    assert.equal(out.c, null);
    assert.equal(out.token, R);
  });

  it('survives cycles and very deep structures', () => {
    const a: any = { x: 1 };
    a.self = a;
    assert.doesNotThrow(() => redactSecrets(a));
    let deep: any = { v: ['sk-', 'ant-api03-abcdefghijklmnopqrstuvwxyz0123456789'].join('') };
    for (let i = 0; i < 500; i++) deep = { n: deep };
    assert.doesNotThrow(() => redactSecrets(deep));
  });
});
