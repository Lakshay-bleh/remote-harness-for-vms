import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { handleUtterance, type AssistantDeps } from './assistant';

function deps(over: Partial<AssistantDeps> = {}) {
  const log: string[] = [];
  const d: AssistantDeps = {
    device: { listApps: async () => ({ apps: [{ label: 'YouTube', package: 'com.yt' }] }), launchPackage: async () => ({ ok: true }) } as never,
    hasComputer: true,
    toComputer: async (text) => (log.push(`computer:${text}`), 'Opening youtube.'),
    toAssistant: async (text) => void log.push(`assistant:${text}`),
    go: (tab) => void log.push(`go:${tab}`),
    ...over,
  };
  return { d, log };
}

describe('handleUtterance', () => {
  it('does phone things on the phone', async () => {
    const { d } = deps();
    assert.deepEqual(await handleUtterance('hey escanor open youtube', d), { ok: true, say: 'Opening YouTube.', kind: 'phone' });
  });

  it('sends "on my computer…" to the computer and speaks its answer', async () => {
    const { d, log } = deps();
    const r = await handleUtterance('on my laptop open youtube', d);
    assert.deepEqual(log, ['computer:open youtube']);
    assert.deepEqual(r, { ok: true, say: 'Opening youtube.', kind: 'computer' });
  });

  it('turns a computer that says "switched off for phones" into one clear sentence that says where to fix it', async () => {
    const off = '“Open apps and websites” is turned off for phones. On your computer, open Escanor Desktop, go to Settings, then Permissions, and switch it on in the Phone column.';
    const { d } = deps({ toComputer: async () => off });
    const r = await handleUtterance('on my pc open youtube', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /Open apps and websites/);
    assert.match(r.say, /Escanor Desktop/);
    assert.match(r.say, /Permissions/);
  });

  it('explains a computer that cannot be reached, and where to look', async () => {
    const { d } = deps({ toComputer: async () => { throw new Error('The computer did not answer. Is it on and online?'); } });
    const r = await handleUtterance('tell my computer to lock', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /not answering/i);
    assert.match(r.say, /Escanor Desktop/);
  });

  it('says plainly that no computer is paired, and how to add one', async () => {
    const { d } = deps({ hasComputer: false });
    const r = await handleUtterance('on my computer open youtube', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /Computers/);
  });

  it('hands questions to the assistant and says so', async () => {
    const { d, log } = deps();
    const r = await handleUtterance('why is checkout slow', d);
    assert.deepEqual(log, ['assistant:why is checkout slow']);
    assert.deepEqual(r, { ok: true, say: 'Asking your Escanor assistant.', kind: 'assistant' });
  });

  it('moves around the app', async () => {
    const { d, log } = deps();
    assert.deepEqual(await handleUtterance('go to my computers', d), { ok: true, say: 'Opening Computers.', kind: 'go' });
    assert.deepEqual(log, ['go:computers']);
  });

  it('handles silence and cancel without doing anything', async () => {
    const { d, log } = deps();
    assert.equal((await handleUtterance('', d)).ok, false);
    assert.deepEqual(await handleUtterance('never mind', d), { ok: true, say: 'Okay.', kind: 'stop' });
    assert.deepEqual(log, []);
  });

  it('speaks the assistant\u2019s answer when it comes back with one', async () => {
    const { d } = deps({ toAssistant: async () => 'Checkout is slow because the database is overloaded.' });
    const r = await handleUtterance('why is checkout slow', d);
    assert.deepEqual(r, { ok: true, say: 'Checkout is slow because the database is overloaded.', kind: 'assistant' });
  });

  it('never throws, even if the assistant call blows up', async () => {
    const { d } = deps({ toAssistant: async () => { throw new Error('offline'); } });
    const r = await handleUtterance('why is it slow', d);
    assert.equal(r.ok, false);
    assert.ok(r.say.length > 0);
  });
});
