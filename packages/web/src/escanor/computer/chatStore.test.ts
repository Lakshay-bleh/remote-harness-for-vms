import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';
import { addTurn, dayLabel, forgetChats, loadChats, MAX_CHATS, MAX_TURNS, newChat, remove, saveChats, tidy, titleFrom, upsert, type Chat } from './chatStore';

class FakeStorage {
  private m = new Map<string, string>();
  getItem(k: string) { return this.m.get(k) ?? null; }
  setItem(k: string, v: string) { this.m.set(k, v); }
  removeItem(k: string) { this.m.delete(k); }
}
const said = (text: string, at = 1): { who: 'you'; text: string; at: number } => ({ who: 'you', text, at });

describe('computer chats', () => {
  beforeEach(() => Object.defineProperty(globalThis, 'localStorage', { value: new FakeStorage(), configurable: true, writable: true }));

  it('names a chat after the first thing said', () => {
    let c = newChat(1, 'a');
    c = addTurn(c, said('What is using my memory?'));
    assert.equal(c.title, 'What is using my memory?');
    c = addTurn(c, { who: 'computer', text: 'Chrome.', at: 2 });
    c = addTurn(c, said('and disk?', 3));
    assert.equal(c.title, 'What is using my memory?');
    assert.equal(c.updatedAt, 3);
  });

  it('shortens a long title to one line', () => {
    assert.equal(titleFrom('x'.repeat(100)).length, 42);
    assert.equal(titleFrom('  a \n\n b '), 'a b');
    assert.equal(titleFrom('   '), 'New chat');
  });

  it('keeps the newest turns when a chat gets very long', () => {
    let c = newChat(1, 'a');
    for (let i = 0; i < MAX_TURNS + 20; i++) c = addTurn(c, said(`m${i}`, i));
    assert.equal(c.turns.length, MAX_TURNS);
    assert.equal(c.turns.at(-1)!.text, `m${MAX_TURNS + 19}`);
  });

  it('lists newest first, hides empty chats, and keeps at most MAX_CHATS', () => {
    const many: Chat[] = Array.from({ length: MAX_CHATS + 5 }, (_, i) => addTurn(newChat(i, `c${i}`), said('hi', i + 10)));
    const t = tidy([...many, newChat(999, 'empty')]);
    assert.equal(t.length, MAX_CHATS);
    assert.equal(t[0].id, `c${MAX_CHATS + 4}`);
    assert.ok(!t.some((c) => c.id === 'empty'));
  });

  it('replaces a chat by id when it changes, and removes one', () => {
    const a = addTurn(newChat(1, 'a'), said('one', 5));
    let list = upsert([], a);
    list = upsert(list, addTurn(a, said('two', 9)));
    assert.equal(list.length, 1);
    assert.equal(list[0].turns.length, 2);
    assert.deepEqual(remove(list, 'a'), []);
  });

  it('survives a restart: saved per computer, and one computer never sees another’s chats', () => {
    saveChats('phone-1', [addTurn(newChat(1, 'a'), said('hi', 2))]);
    saveChats('phone-2', [addTurn(newChat(1, 'b'), said('yo', 2))]);
    assert.equal(loadChats('phone-1')[0].id, 'a');
    assert.equal(loadChats('phone-2')[0].id, 'b');
    forgetChats('phone-1');
    assert.deepEqual(loadChats('phone-1'), []);
    assert.equal(loadChats('phone-2').length, 1);
  });

  it('ignores damaged storage', () => {
    localStorage.setItem('escanor.computer.chats.v1:x', '{{{not json');
    assert.deepEqual(loadChats('x'), []);
    localStorage.setItem('escanor.computer.chats.v1:y', JSON.stringify([{ id: 1 }, { id: 'ok', title: 't', turns: [{ who: 'you', text: 'hi', at: 1 }], createdAt: 1, updatedAt: 1 }]));
    assert.deepEqual(loadChats('y').map((c) => c.id), ['ok']);
  });

  it('labels days for the history list', () => {
    const now = new Date(2026, 9, 4, 15).getTime();
    assert.equal(dayLabel(new Date(2026, 9, 4, 8).getTime(), now), 'Today');
    assert.equal(dayLabel(new Date(2026, 9, 3, 23).getTime(), now), 'Yesterday');
    assert.equal(dayLabel(new Date(2026, 9, 1).getTime(), now), 'Earlier this week');
  });
});
