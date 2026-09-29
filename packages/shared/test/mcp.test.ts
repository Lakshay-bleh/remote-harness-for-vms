import assert from 'node:assert/strict';
import test from 'node:test';
import { agentSupportsMcp, parseMcpServerInput, toMcpServerDto } from '../src/protocol.ts';

const ok = (name: string, body: unknown) => {
  const r = parseMcpServerInput(name, body);
  assert.ok(r.ok, r.ok ? '' : r.error);
  return r.server;
};
const bad = (name: string, body: unknown) => {
  const r = parseMcpServerInput(name, body);
  assert.equal(r.ok, false, `expected ${JSON.stringify(body)} to be rejected`);
  return r.ok ? '' : r.error;
};

test('a server is accepted with sensible defaults', () => {
  const s = ok('escanor', { url: 'https://mcp.escanor.in/' });
  assert.equal(s.autoAllow, true);
  assert.equal(s.alwaysLoad, true);
  assert.equal(s.url, 'https://mcp.escanor.in/');
});

test('flags can be turned off explicitly', () => {
  const s = ok('escanor', { url: 'https://x.example/', autoAllow: false, alwaysLoad: false });
  assert.equal(s.autoAllow, false);
  assert.equal(s.alwaysLoad, false);
});

test('names must survive as a Claude Code tool namespace', () => {
  for (const name of ['', 'Escanor', 'has space', '-lead', 'a'.repeat(33), 'dots.not.ok', '../x']) bad(name, { url: 'https://x/' });
  for (const name of ['escanor', 'a', 'my_server-2', '0abc']) ok(name, { url: 'https://x/' });
});

test('only http(s) URLs without embedded credentials', () => {
  bad('s', {});
  bad('s', { url: 42 });
  bad('s', { url: 'not a url' });
  bad('s', { url: 'ftp://x/' });
  bad('s', { url: 'file:///etc/passwd' });
  bad('s', { url: 'https://user:pw@x.example/' });
  ok('s', { url: 'http://127.0.0.1:8787/mcp' });
});

test('headers cannot smuggle extra headers', () => {
  bad('s', { url: 'https://x/', headers: { 'X-A': 'v\r\nEvil: 1' } });
  bad('s', { url: 'https://x/', headers: { 'X-A': 'v\nEvil: 1' } });
  bad('s', { url: 'https://x/', headers: { 'bad name': 'v' } });
  bad('s', { url: 'https://x/', headers: { A: 1 } });
  bad('s', { url: 'https://x/', headers: ['x'] });
  bad('s', { url: 'https://x/', headers: Object.fromEntries(Array.from({ length: 17 }, (_, i) => [`H${i}`, 'v'])) });
  assert.deepEqual(ok('s', { url: 'https://x/', headers: { Authorization: 'Bearer t' } }).headers, { Authorization: 'Bearer t' });
});

test('the DTO never carries header values', () => {
  const dto = toMcpServerDto({ name: 'escanor', url: 'https://x/', headers: { Authorization: 'Bearer secret' }, updatedAt: 't' });
  assert.deepEqual(dto.headerNames, ['Authorization']);
  assert.ok(!JSON.stringify(dto).includes('secret'));
});

test('agents before 0.3.0 are reported as unable to install MCP servers', () => {
  for (const v of ['0.2.0', '0.2.9', '0.1.0', '', null, undefined, 'garbage']) assert.equal(agentSupportsMcp(v as never), false, String(v));
  for (const v of ['0.3.0', '0.3.1', '0.10.0', '1.0.0', '1']) assert.equal(agentSupportsMcp(v), true, v);
});
