import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { pickComputer, sameName } from './computerTarget';

const c = (id: string, name: string, alias = '') => ({ id, name, alias });

describe('which computer a voice request goes to', () => {
  const all = [c('a', 'DESKTOP-7Q2', 'Gaming PC'), c('b', 'Lakshay’s MacBook Pro'), c('d', 'Work Laptop')];

  it('the one named in the sentence, by the name given on this phone or its own', () => {
    assert.equal(pickComputer(all, 'gaming pc', 'b')?.id, 'a');
    assert.equal(pickComputer(all, "lakshay's macbook pro", 'a')?.id, 'b');
    assert.equal(pickComputer(all, 'DESKTOP-7Q2', null)?.id, 'a');
  });

  it('else the one used last, else the first', () => {
    assert.equal(pickComputer(all, null, 'd')?.id, 'd');
    assert.equal(pickComputer(all, 'no such computer', 'd')?.id, 'd');
    assert.equal(pickComputer(all, null, 'unpaired-since')?.id, 'a');
    assert.equal(pickComputer(all, null, null)?.id, 'a');
    assert.equal(pickComputer([], null, null), null);
  });

  it('compares names the way they are spoken', () => {
    assert.ok(sameName('Lakshay’s MacBook Pro', "lakshay's macbook pro"));
    assert.ok(sameName('Work-Laptop', 'work laptop'));
    assert.ok(!sameName('Work Laptop', 'work'));
  });
});
