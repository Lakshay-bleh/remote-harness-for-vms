import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SessionRegistry } from './registry.js';

const entry = (id: string) => ({ sessionId: id, cwd: '/w', title: id, createdAt: 'x', accountId: 'default' });
const tmp = () => mkdtempSync(join(tmpdir(), 'registry-test-'));

describe('SessionRegistry', () => {
  it('persists atomically (always valid JSON, no temp files left behind)', () => {
    const dir = tmp();
    const r = new SessionRegistry(dir);
    r.upsert(entry('a'));
    r.upsert(entry('b'));
    assert.equal(JSON.parse(readFileSync(join(dir, 'sessions.json'), 'utf-8')).length, 2);
    assert.deepEqual(readdirSync(dir).filter((f) => f.includes('.tmp')), []);
    assert.equal(new SessionRegistry(dir).all().length, 2);
  });

  it('recovers from the backup when the main file is corrupt', () => {
    const dir = tmp();
    const r = new SessionRegistry(dir);
    r.upsert(entry('a'));
    r.upsert(entry('b')); // .bak now holds the state with just "a"
    writeFileSync(join(dir, 'sessions.json'), '{ truncated');
    const recovered = new SessionRegistry(dir);
    assert.ok(recovered.get('a'), 'session from the backup must survive');
  });

  it('quarantines (never silently discards) an unreadable file with no backup', () => {
    const dir = tmp();
    writeFileSync(join(dir, 'sessions.json'), 'garbage');
    const r = new SessionRegistry(dir);
    assert.equal(r.all().length, 0);
    assert.ok(readdirSync(dir).some((f) => f.startsWith('sessions.json.corrupt-')), 'corrupt file kept for manual recovery');
    r.upsert(entry('c'));
    assert.ok(existsSync(join(dir, 'sessions.json')));
  });

  it('skips malformed entries instead of failing the whole load', () => {
    const dir = tmp();
    writeFileSync(join(dir, 'sessions.json'), JSON.stringify([entry('ok'), null, { nope: 1 }]));
    const r = new SessionRegistry(dir);
    assert.deepEqual(r.all().map((e) => e.sessionId), ['ok']);
  });
});
