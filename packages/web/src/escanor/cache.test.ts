import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';
import { clearCache, dropCache, readCache, writeCache } from './cache';

class FakeStorage {
  private m = new Map<string, string>();
  get length() { return this.m.size; }
  key(i: number) { return [...this.m.keys()][i] ?? null; }
  getItem(k: string) { return this.m.get(k) ?? null; }
  setItem(k: string, v: string) { this.m.set(k, v); }
  removeItem(k: string) { this.m.delete(k); }
}

describe('cache', () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, 'localStorage', { value: new FakeStorage(), configurable: true, writable: true });
    clearCache();
  });
  const policy = { key: 'list', ttlMs: 60_000, maxAgeMs: 600_000 };

  it('trusts an entry younger than its time to live and refreshes an older one', () => {
    writeCache('list', [1, 2], 1_000);
    assert.deepEqual(readCache(policy, 1_000 + 59_000), { value: [1, 2], age: 59_000, fresh: true });
    assert.equal(readCache(policy, 1_000 + 61_000)?.fresh, false);
  });

  it('forgets an entry past its maximum age, and one dated in the future', () => {
    writeCache('list', 'x', 1_000);
    assert.equal(readCache(policy, 1_000 + 601_000), null);
    assert.equal(readCache(policy, 500), null);
  });

  it('survives a restart of the app: it is read back from storage', () => {
    writeCache('list', { a: 1 }, 1_000);
    // a new process has an empty memory but the same storage
    const stored = (globalThis.localStorage as unknown as FakeStorage).getItem('escanor.cache.v1:list');
    assert.ok(stored);
    assert.deepEqual(readCache<{ a: number }>(policy, 2_000)?.value, { a: 1 });
  });

  it('drops by prefix and clears everything', () => {
    writeCache('computer:a:groups', 1);
    writeCache('computer:a:activity', 2);
    writeCache('computer:b:groups', 3);
    dropCache('computer:a:');
    assert.equal(readCache({ key: 'computer:a:groups', ttlMs: 1 }), null);
    assert.equal(readCache({ key: 'computer:a:activity', ttlMs: 1 }), null);
    assert.equal(readCache({ key: 'computer:b:groups', ttlMs: 1 })?.value, 3);
    clearCache();
    assert.equal(readCache({ key: 'computer:b:groups', ttlMs: 1 }), null);
    assert.equal((globalThis.localStorage as unknown as FakeStorage).length, 0);
  });

  it('keeps working when storage refuses writes', () => {
    Object.defineProperty(globalThis, 'localStorage', { value: { getItem: () => null, setItem: () => { throw new Error('full'); }, removeItem: () => undefined, key: () => null, length: 0 }, configurable: true, writable: true });
    writeCache('big', 'still in memory');
    assert.equal(readCache({ key: 'big', ttlMs: 1000 })?.value, 'still in memory');
  });
});
