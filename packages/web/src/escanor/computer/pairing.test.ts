import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { b64u, formatCode, pairProof, pairSelector, pairingKey, parseCode, randomBytes, seal } from './lib/secure';
import type { CloudDirectory } from './lib/client';
import { normalizeAddress, pairComputer, parseEntry } from './pairing';

/** A computer showing a code: it checks the proof like the real desktop does and seals a device key to the code. */
function fakeDesktop(id = 'agent-1', name = 'Work Laptop') {
  const secret = randomBytes(20);
  const code = formatCode(secret);
  const asked: string[] = [];
  const cloud: CloudDirectory = {
    computers: async () => [{ id, name, online: true }],
    pair: async (agentId, body) => {
      asked.push(agentId);
      if (agentId !== id) throw new Error('Not this computer.');
      if (body.sel !== (await pairSelector(secret))) throw new Error('Not this computer.');
      const proof = await pairProof(secret, body.nonce, body.name);
      if (b64u.encode(proof) !== body.proof) throw new Error('That code did not match.');
      return { deviceId: 'dev-1', sealedKey: await seal(await pairingKey(secret), randomBytes(32), 'pair:dev-1') };
    },
  };
  return { code, cloud, asked, secret };
}

describe('parseEntry', () => {
  it('reads a typed code in any case, with or without dashes and spaces', () => {
    const { code } = fakeDesktop();
    for (const typed of [code, code.toLowerCase(), code.replace(/-/g, ''), `  ${code.replace(/-/g, ' ')}  `]) assert.equal(parseEntry(typed)?.code, code); // always the canonical form
  });

  it('reads a scanned QR payload, keeping the computer and its addresses', () => {
    const { code } = fakeDesktop();
    const e = parseEntry(JSON.stringify({ v: 1, code, machine: 'Work Laptop', lan: ['192.168.1.20:47625'], agentId: 'agent-1' }));
    assert.deepEqual(e?.payload, { v: 1, code, machine: 'Work Laptop', lan: ['192.168.1.20:47625'], agentId: 'agent-1' });
  });

  it('rejects nonsense, a code of the wrong length and foreign QR codes', () => {
    for (const bad of ['', 'hello', 'ABCD-EFGH', 'https://example.com/x', '{"a":1}', JSON.stringify({ v: 2, code: 'x' })]) assert.equal(parseEntry(bad), null, bad);
  });
});

describe('normalizeAddress', () => {
  it('accepts host:port and rejects anything that is not one', () => {
    assert.equal(normalizeAddress(' 192.168.1.20:47625 '), '192.168.1.20:47625');
    assert.equal(normalizeAddress('http://192.168.1.20:47625/'), '192.168.1.20:47625');
    for (const bad of ['', '192.168.1.20', 'nonsense', '192.168.1.20:99999', 'a b:1']) assert.equal(normalizeAddress(bad), null, bad);
  });
});

describe('pairComputer', () => {
  it('pairs from anywhere with just the code (the default): no address involved', async () => {
    const d = fakeDesktop();
    const paired = await pairComputer(parseEntry(d.code)!, 'My Phone', { mode: 'cloud', cloud: d.cloud });
    assert.equal(paired.agentId, 'agent-1');
    assert.equal(paired.name, 'Work Laptop');
    assert.deepEqual(paired.lan, []);
  });

  it('does not ask for an address in cloud mode even when the person typed one', async () => {
    const d = fakeDesktop();
    const paired = await pairComputer(parseEntry(d.code)!, 'My Phone', { mode: 'cloud', cloud: d.cloud, lanAddress: '10.0.0.5:47625' });
    assert.deepEqual(paired.lan, []);
  });

  it('local mode needs an address (typed or in the QR) and says so', async () => {
    const d = fakeDesktop();
    await assert.rejects(pairComputer(parseEntry(d.code)!, 'P', { mode: 'lan', cloud: d.cloud }), /address/i);
    await assert.rejects(pairComputer(parseEntry(d.code)!, 'P', { mode: 'lan', cloud: d.cloud, lanAddress: 'nonsense' }), /address/i);
  });

  it('a scanned QR goes straight to its computer, and a wrong code is reported (never retried on Wi-Fi)', async () => {
    const d = fakeDesktop();
    const wrong = formatCode(randomBytes(20));
    const e = parseEntry(JSON.stringify({ v: 1, code: wrong, machine: 'Work Laptop', lan: ['192.168.1.20:47625'], agentId: 'agent-1' }))!;
    await assert.rejects(pairComputer(e, 'P', { mode: 'cloud', cloud: d.cloud }), /not showing on any of your computers/);
    assert.deepEqual(d.asked, ['agent-1']);
  });

  it('falls back to the QR’s local addresses only when the cloud itself cannot be reached', async () => {
    const d = fakeDesktop();
    const offline: CloudDirectory = { computers: async () => Promise.reject(new Error('Could not reach Escanor. Check your connection.')), pair: async () => Promise.reject(new Error('Could not reach Escanor. Check your connection.')) };
    const e = parseEntry(JSON.stringify({ v: 1, code: d.code, machine: 'Work Laptop', lan: ['192.168.1.20:47625'], agentId: 'agent-1' }))!;
    let triedLan: string | null = null;
    const env = { fetch: (async (url: string) => ((triedLan = String(url)), Promise.reject(new Error('network failed')))) as unknown as typeof fetch, lanTimeoutMs: 50 };
    await assert.rejects(pairComputer(e, 'P', { mode: 'cloud', cloud: offline, env }));
    assert.match(triedLan ?? '', /192\.168\.1\.20:47625\/pair/);
  });

  it('parseCode round-trips what the desktop shows', () => {
    const d = fakeDesktop();
    assert.deepEqual(parseCode(d.code), d.secret);
  });
});
