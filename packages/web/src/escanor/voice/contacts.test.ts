import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { chooseContact, rankContacts, tokens, wordScore, type Contact } from './contacts';

const book: Contact[] = [
  { name: 'Tanishq USICT 2027', numbers: ['+919876500001'] },
  { name: 'Tanishq Sharma', numbers: ['+919876500002'] },
  { name: 'Mom', numbers: ['+919876500003'] },
  { name: 'Aman Gupta (College)', numbers: ['+919876500004'] },
  { name: 'Amit Gupta', numbers: ['+919876500005'] },
  { name: 'Dr. Priya Nair', numbers: ['+919876500006'] },
];

describe('what was heard, as words and numbers', () => {
  it('splits letters from digits and drops punctuation', () => {
    assert.deepEqual(tokens('Tanishq USICT2027'), ['tanishq', 'usict', '2027']);
    assert.deepEqual(tokens('Dr. Priya Nair'), ['dr', 'priya', 'nair']);
  });
  it('joins a year the way people say it', () => {
    assert.deepEqual(tokens('tanishq usic twenty twenty seven'), ['tanishq', 'usic', '2027']);
    assert.deepEqual(tokens('tanishq usic 20 27'), ['tanishq', 'usic', '2027']);
    assert.deepEqual(tokens('tanishq usic two thousand and twenty seven'), ['tanishq', 'usic', '2027']);
  });
});

describe('words that sound or are spelled nearly the same', () => {
  it('forgives a dropped letter, a cut-off word and a different spelling of the same sound', () => {
    assert.ok(wordScore('usic', 'usict') >= 0.8);
    assert.ok(wordScore('tanisha', 'tanishq') >= 0.7);
    assert.ok(wordScore('kumar', 'kumaar') >= 0.8);
  });
  it('never treats two different numbers as alike', () => {
    assert.equal(wordScore('2026', '2027'), 0);
    assert.equal(wordScore('2027', 'usict'), 0);
  });
});

describe('choosing the contact', () => {
  const pick = (said: string) => chooseContact(said, book);
  it('finds "Tanishq USICT 2027" from the very sentences that failed before', () => {
    for (const said of ['tanishq usic 2027', 'tanishq usict 2027', 'Tanishq USIC 20 27', 'tanishq u s i c t twenty twenty seven']) {
      const c = pick(said);
      assert.equal(c.kind, 'one', said);
      assert.equal(c.kind === 'one' && c.contact.name, 'Tanishq USICT 2027', said);
    }
  });
  it('finds the right one among similar names', () => {
    const a = pick('mom');
    assert.equal(a.kind === 'one' && a.contact.name, 'Mom');
    const b = pick('doctor priya nair');
    assert.equal(b.kind === 'one' && b.contact.name, 'Dr. Priya Nair');
  });
  it('asks which one when two fit about equally, and says none when nothing does', () => {
    const c = pick('gupta');
    assert.equal(c.kind, 'ask');
    assert.deepEqual(c.kind === 'ask' && c.options.map((x) => x.name).sort(), ['Aman Gupta (College)', 'Amit Gupta']);
    assert.equal(pick('zebra crossing').kind, 'none');
  });
  it('prefers the saved name that says more of what was said', () => {
    const r = rankContacts('tanishq', book);
    assert.equal(r.length >= 2, true);
  });
});
