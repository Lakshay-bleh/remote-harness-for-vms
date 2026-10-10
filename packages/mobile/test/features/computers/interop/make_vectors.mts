/**
 * Generates fixtures/vectors.json: what the TypeScript phone library (the desktop's own copy, kept in sync with the reference app)
 * produces for fixed inputs. The Dart port must produce the same bytes and open what this produced.
 *
 * Run from any scratch directory (nothing is written next to the reference):
 *   ~/.nvm/versions/node/v22.23.2/bin/node test/features/computers/interop/node_modules/.bin/tsx \
 *     /home/lakshay/Desktop/StartUp/escanor-mobile/test/features/computers/interop/make_vectors.mts > vectors.json
 */
const REF = '/home/lakshay/Desktop/StartUp/escanor-mobile-reference/packages/web/src/escanor/computer/lib';

// Deterministic "random" bytes, so every seal's IV and every relay id is reproducible. Recorded in the output as it is used.
let counter = 0;
const draws: string[] = [];
Object.defineProperty(globalThis.crypto, 'getRandomValues', {
  configurable: true,
  value: <T extends ArrayBufferView>(arr: T): T => {
    const u = new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);
    for (let i = 0; i < u.length; i++) u[i] = (counter++ * 37 + 11) & 255;
    draws.push(Buffer.from(u).toString('hex'));
    return arr;
  },
});

const S = await import(`${REF}/secure.ts`);
const R = await import(`${REF}/relay-seal.ts`);

const hex = (b: Uint8Array) => Buffer.from(b).toString('hex');
const bytes = (n: number, k = 1) => Uint8Array.from({ length: n }, (_, i) => (i * k + 3) & 255);
const lastDraw = () => draws[draws.length - 1];

const out: Record<string, unknown> = {};

// ---- base64url
out.b64u = [0, 1, 2, 3, 4, 5, 16, 31, 32, 65].map((n) => ({ hex: hex(bytes(n, 53)), b64u: S.b64u.encode(bytes(n, 53)) }));

// ---- codes
const secret = bytes(20, 7);
const code = S.formatCode(secret);
out.code = { secretHex: hex(secret), code, parsedHex: hex(S.parseCode(code.toLowerCase().replace(/-/g, ' '))) };

// ---- hmac / hkdf
out.hmac = [
  { keyHex: hex(bytes(32)), parts: ['pair', 'abc', 'Pixel'], outHex: hex(await S.hmac(bytes(32), 'pair', 'abc', 'Pixel')) },
  { keyHex: hex(bytes(32)), parts: ['ab', 'c'], outHex: hex(await S.hmac(bytes(32), 'ab', 'c')) },
  { keyHex: hex(bytes(32)), parts: ['a', 'bc'], outHex: hex(await S.hmac(bytes(32), 'a', 'bc')) },
  { keyHex: hex(bytes(20, 7)), parts: ['sel'], outHex: hex(await S.hmac(bytes(20, 7), 'sel')) },
  { keyHex: hex(bytes(32)), parts: ['“Open apps” ünïcode ✓'], outHex: hex(await S.hmac(bytes(32), '“Open apps” ünïcode ✓')) },
];
out.hkdf = [
  { secretHex: hex(bytes(32)), salt: 'escanor-relay-v1', info: 'relay key', outHex: hex(await S.hkdf(bytes(32), 'escanor-relay-v1', 'relay key')) },
  { secretHex: hex(bytes(20, 7)), salt: 'escanor-pair-v1', info: 'pairing key', outHex: hex(await S.hkdf(bytes(20, 7), 'escanor-pair-v1', 'pairing key')) },
  { secretHex: hex(bytes(32, 3)), saltHex: hex(bytes(130, 9)), info: 'escanor-approve-v1 key', outHex: hex(await S.hkdf(bytes(32, 3), bytes(130, 9), 'escanor-approve-v1 key')) },
];

// ---- named derivations
const deviceKey = bytes(32, 13);
const nonceC = 'bm9uY2UtY2xpZW50LTE2';
const nonceS = 'c2VydmVyLW5vbmNlLTE2';
out.derive = {
  secretHex: hex(secret),
  deviceKeyHex: hex(deviceKey),
  deviceKeyB64u: S.b64u.encode(deviceKey),
  nonceC,
  nonceS,
  pairNonce: 'cGFpci1ub25jZQ',
  deviceName: 'Android phone',
  pairingKeyHex: hex(await S.pairingKey(secret)),
  pairProofB64u: S.b64u.encode(await S.pairProof(secret, 'cGFpci1ub25jZQ', 'Android phone')),
  pairSelector: await S.pairSelector(secret),
  relayKeyHex: hex(await S.relayKey(deviceKey)),
  serverProofB64u: S.b64u.encode(await S.serverProof(deviceKey, nonceC, nonceS)),
  clientProofB64u: S.b64u.encode(await S.clientProof(deviceKey, nonceC, nonceS)),
  sessionKeyHex: hex(await S.sessionKey(deviceKey, nonceC, nonceS)),
};

// ---- AES-GCM with known IVs
const seals: unknown[] = [];
for (const [plain, aad] of [
  ['hello', ''],
  ['', 'aad-only'],
  ['{"s":1,"m":{"t":"ping"}}', 'lan:dev-1:c2s'],
  ['“Open apps and websites” is turned off for phones. ✓ ünïcode', 'relay:dev-1:res'],
  ['x'.repeat(1000), 'long'],
] as const) {
  const key = bytes(32, 29);
  const sealed = await S.seal(key, plain, aad);
  seals.push({ keyHex: hex(key), plain, aad, ivHex: lastDraw(), sealed });
}
out.seal = seals;

// ---- the device key, sealed to the pairing code (what the computer answers a pairing with)
{
  const sealed = await S.seal(await S.pairingKey(secret), deviceKey, 'pair:dev-1');
  out.sealedDeviceKey = { secretHex: hex(secret), deviceId: 'dev-1', ivHex: lastDraw(), sealed, deviceKeyHex: hex(deviceKey) };
}

// ---- LAN frames, both directions, under the session key
{
  const sk = await S.sessionKey(deviceKey, nonceC, nonceS);
  const s2cPlain = JSON.stringify({ s: 1, m: { t: 'hello', machine: { name: 'Work Laptop', hostname: 'box', os: 'linux', appVersion: '0.4.0' } } });
  const s2c = await S.seal(sk, s2cPlain, 'lan:dev-1:s2c');
  const s2cIv = lastDraw();
  const c2sPlain = JSON.stringify({ s: 1, m: { t: 'chat', id: 'abc', text: 'What is using my memory?', fresh: true } });
  const c2s = await S.seal(sk, c2sPlain, 'lan:dev-1:c2s');
  out.lan = { deviceId: 'dev-1', s2c: { plain: s2cPlain, ivHex: s2cIv, sealed: s2c }, c2s: { plain: c2sPlain, ivHex: lastDraw(), sealed: c2s } };
}

// ---- cloud relay
{
  const before = draws.length;
  const req = await R.sealRelayRequest('dev-1', deviceKey, { t: 'ping' }, 1_790_000_000_000);
  const [idDraw, ivDraw] = draws.slice(before);
  const opened = await R.openRelayRequest('dev-1', deviceKey, req.sealed);
  const replies = [{ t: 'pong' }, { t: 'reply', id: 'x', reply: 'Chrome ✓', listenAgain: false }];
  const res = await R.sealRelayResponse('dev-1', deviceKey, { id: req.id, ts: 1_790_000_001_000, replies });
  out.relay = {
    deviceId: 'dev-1',
    deviceKeyHex: hex(deviceKey),
    request: { id: req.id, idHex: idDraw, ivHex: ivDraw, ts: 1_790_000_000_000, m: { t: 'ping' }, plain: JSON.stringify(opened), sealed: req.sealed },
    response: { id: req.id, ts: 1_790_000_001_000, replies, ivHex: lastDraw(), plain: JSON.stringify({ id: req.id, ts: 1_790_000_001_000, replies }), sealed: res },
  };
}

// ---- pairing by approval: ECDH P-256 + the confirmation number
{
  const gen = async () => {
    const pair = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'])) as CryptoKeyPair;
    const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
    return { priv: pair.privateKey, pub: new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)), d: Buffer.from(jwk.d!, 'base64url').toString('hex') };
  };
  const phone = await gen();
  const machine = await gen();
  const shared = await S.ecdhShared(phone.priv, machine.pub);
  const shared2 = await S.ecdhShared(machine.priv, phone.pub);
  if (hex(shared) !== hex(shared2)) throw new Error('ECDH mismatch');
  const sec = await S.approvalSecrets(shared, phone.pub, machine.pub);
  const sealedKey = await S.seal(sec.key, deviceKey, 'pair:dev-9');
  out.ecdh = {
    phone: { dHex: phone.d, pubB64u: S.b64u.encode(phone.pub) },
    machine: { dHex: machine.d, pubB64u: S.b64u.encode(machine.pub) },
    sharedHex: hex(shared),
    keyHex: hex(sec.key),
    confirm: sec.confirm,
    sealedKey,
    sealedKeyIvHex: lastDraw(),
    deviceId: 'dev-9',
    deviceKeyHex: hex(deviceKey),
  };
}

process.stdout.write(JSON.stringify(out, null, 1) + '\n');
