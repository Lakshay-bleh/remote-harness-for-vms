import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { autonomousBlockReason, BLOCKED_COMMANDS, BLOCKED_PATHS, type Blocked } from '../src/autonomy.ts';

// The phone keeps its own copy of the list (Dart cannot import this one). Read it out of its source and compare.
const dart = readFileSync(new URL('../../mobile/lib/features/machines/autonomy.dart', import.meta.url), 'utf8');

function dartList(name: string): Blocked[] {
  const named = new Map<string, Blocked>();
  for (const m of dart.matchAll(/final (_\w+) = RegExp\(r'((?:[^'\\]|\\.)*)'(, caseSensitive: false)?\);/g)) {
    named.set(m[1], { source: m[2], ...(m[3] ? { ignoreCase: true } : {}), why: '' });
  }
  const body = dart.split(`${name} = [`)[1]?.split('\n];')[0];
  assert.ok(body, `${name} not found in autonomy.dart`);
  const out: Blocked[] = [];
  for (const m of body.matchAll(/\((?:RegExp\(r'((?:[^'\\]|\\.)*)'(, caseSensitive: false)?\)|(_\w+)), '([^']*)'\)/g)) {
    const base = m[3] ? named.get(m[3]) : { source: m[1], ...(m[2] ? { ignoreCase: true } : {}) };
    assert.ok(base, `unknown pattern ${m[3]}`);
    out.push({ source: base.source, ...(base.ignoreCase ? { ignoreCase: true } : {}), why: m[4] });
  }
  return out;
}

describe('the Autonomous blocklist', () => {
  it('is the same list the phone uses', () => {
    assert.deepEqual(dartList('_blockedCommands'), BLOCKED_COMMANDS);
    assert.deepEqual(dartList('_blockedPaths'), BLOCKED_PATHS);
    assert.equal(BLOCKED_COMMANDS.length, 13);
  });

  it('blocks what cannot be taken back and lets ordinary work through', () => {
    const bash = (command: string) => autonomousBlockReason('Bash', { command });
    for (const c of ['rm -rf /', 'sudo rm -rf ~/', 'git push --force origin main', 'git push origin main -f', 'psql -c "DROP DATABASE app"', 'ufw disable', 'mkfs.ext4 /dev/sdb1', 'reboot']) {
      assert.ok(bash(c), `${c} must be blocked`);
    }
    for (const c of ['npm test', 'rm -rf node_modules', 'git push origin feature/x', 'git push --force origin feature/x', 'docker compose up -d']) {
      assert.equal(bash(c), null, `${c} must be allowed`);
    }
    assert.match(bash('git push -f origin main') ?? '', /force-pushes over a main branch/);
    assert.ok(autonomousBlockReason('Edit', { file_path: '/home/u/.ssh/authorized_keys' }));
    assert.ok(autonomousBlockReason('Write', { file_path: '/etc/sudoers' }));
    assert.equal(autonomousBlockReason('Write', { file_path: '/home/u/app/main.ts' }), null);
    assert.equal(autonomousBlockReason('WebFetch', { url: 'https://example.com' }), null);
    assert.equal(autonomousBlockReason('Bash', undefined), null);
  });
});
