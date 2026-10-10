// The installer takes HUB_URL / HUB_TOKEN from the environment (the Escanor app hands out a command that sets them) and writes
// them into .env. They must never be able to run commands, add settings, or leave the file readable by other users.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';

const lib = new URL('../envfile.sh', import.meta.url).pathname;
const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'envfile-'));
  dirs.push(d);
  return d;
};
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const bash = (script: string, env: Record<string, string> = {}) =>
  spawnSync('bash', ['-c', `set -euo pipefail; source "${lib}"; ${script}`], { env: { PATH: process.env.PATH ?? '', ...env }, encoding: 'utf8' });

test('set_env_var replaces a value without interpreting it (no sed, no shell)', () => {
  const dir = tmp();
  const file = join(dir, '.env');
  const pwn = join(dir, 'pwned');
  writeFileSync(file, 'HUB_URL=wss://old.example/agent\nHUB_TOKEN=oldtoken\nVM_NAME=box\n');
  for (const evil of [`x|e;touch ${pwn};#`, `x\\n&y`, `a|b&c\\d`, '$(touch ' + pwn + ')', '`touch ' + pwn + '`', `'; touch ${pwn}; '`]) {
    const r = bash(`set_env_var "${file}" HUB_URL "$VALUE"`, { VALUE: evil });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(existsSync(pwn), false, `command ran for ${JSON.stringify(evil)}`);
    const lines = readFileSync(file, 'utf8').split('\n');
    assert.equal(lines.filter((l) => l.startsWith('HUB_URL=')).length, 1);
    assert.equal(lines.find((l) => l.startsWith('HUB_URL=')), `HUB_URL=${evil}`, 'stored verbatim');
    assert.ok(lines.includes('HUB_TOKEN=oldtoken') && lines.includes('VM_NAME=box'), 'other settings untouched');
  }
});

test('set_env_var appends a missing key and keeps the file owner-only', () => {
  const dir = tmp();
  const file = join(dir, '.env');
  writeFileSync(file, 'VM_NAME=box\n', { mode: 0o644 });
  assert.equal(bash(`set_env_var "${file}" HUB_TOKEN abc123`).status, 0);
  assert.match(readFileSync(file, 'utf8'), /^VM_NAME=box\nHUB_TOKEN=abc123\n$/);
  assert.equal(statSync(file).mode & 0o077, 0);
});

test('values that could smuggle in extra settings or commands are refused', () => {
  const bad: Record<string, string[]> = {
    url: ['http://x.example/agent', 'wss://x.example/agent\nWORKSPACE_ROOT=/', 'wss://x.example/ag ent', 'wss://x|e;id', 'wss://', 'ws://$(id).example/', ''],
    token: ['short', 'tok\nWORKSPACE_ROOT=/', 'a b a b a b a b a b a b', 'abcdefghijklmnop|id', 'abcdefghijklmnop`id`', ''],
    vmname: ['', '-x', 'has space', 'a;b', 'a\nb', 'a'.repeat(101), '../x'],
    apikey: ['key\nWORKSPACE_ROOT=/', 'k e y', 'k;id', '$(id)'],
    path: ['', 'a\nb', '/ok\nWORKSPACE_ROOT=/'],
    mode: ['', 'yolo', 'bypassPermissions\nWORKSPACE_ROOT=/', 'default;id', 'BYPASSPERMISSIONS', ' default'],
  };
  const fn: Record<string, string> = { url: 'valid_hub_url', token: 'valid_hub_token', vmname: 'valid_vm_name', apikey: 'valid_api_key', path: 'valid_path', mode: 'valid_permission_mode' };
  for (const [kind, values] of Object.entries(bad)) {
    for (const v of values) {
      if (kind === 'apikey' && v === '') continue;
      const r = bash(`${fn[kind]} "$VALUE"`, { VALUE: v });
      assert.notEqual(r.status, 0, `${kind} ${JSON.stringify(v)} must be refused`);
    }
  }
});

test('ordinary values are accepted', () => {
  const ok: Array<[string, string]> = [
    ['valid_hub_url', 'wss://hub.example.com/agent'], ['valid_hub_url', 'ws://127.0.0.1:8787/agent'], ['valid_hub_url', 'wss://hub.example.com:8443/a/b'],
    ['valid_hub_token', 'kQ3v9x_-ABCdef0123456789+/='], ['valid_vm_name', 'incident-4821.web_1'], ['valid_api_key', ''], ['valid_api_key', 'sk-ant-api03-AbC_dEf-123'],
    ['valid_path', '/home/me/projects'], ['valid_path', '/srv/my projects/x'],
    ['valid_permission_mode', 'default'], ['valid_permission_mode', 'bypassPermissions'], ['valid_permission_mode', 'auto'],
  ];
  for (const [f, v] of ok) assert.equal(bash(`${f} "$VALUE"`, { VALUE: v }).status, 0, `${f} ${v}`);
});
