import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { beforeEach } from 'node:test';
import { forgetPending, handleUtterance, type AssistantDeps } from './assistant';

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


describe('the server\u2019s fast replies', () => {
  it('speaks a chat answer straight away, without waking the full assistant', async () => {
    const { d, log } = deps({ resolve: async () => ({ source: 'rules', say: "I'm doing great, thanks for asking.", actions: [], needs: null, chat: true }) });
    const r = await handleUtterance('how are you', d);
    assert.deepEqual(r, { ok: true, say: "I'm doing great, thanks for asking.", kind: 'chat' });
    assert.ok(!log.some((l) => l.startsWith('assistant:')));
  });

  it('acknowledges a job at once and speaks the assistant\u2019s answer when it arrives', async () => {
    const said: string[] = [];
    const { d } = deps({
      resolve: async () => ({ source: 'llm', say: 'Checking your services.', actions: [], needs: null, delegate: true }),
      toAssistant: async () => 'Three of your five services are active.',
      ack: async (t) => void said.push(t),
    });
    const r = await handleUtterance('can you check how many services are active', d);
    assert.deepEqual(said, ['Checking your services.']);
    assert.deepEqual(r, { ok: true, say: 'Three of your five services are active.', kind: 'assistant' });
  });

  it('starts the job while the acknowledgement is still being spoken', async () => {
    const order: string[] = [];
    const { d } = deps({
      resolve: async () => ({ source: 'llm', say: 'On it.', actions: [], needs: null, delegate: true }),
      toAssistant: async () => (order.push('job started'), 'done'),
      ack: async () => (order.push('ack began'), new Promise<void>((r) => setTimeout(r, 20))),
    });
    await handleUtterance('check my deployments', d);
    assert.deepEqual(order.slice(0, 2), ['job started', 'ack began']);
  });

  it('still answers with the assistant\u2019s own words if the acknowledgement could not be spoken', async () => {
    const { d } = deps({ resolve: async () => ({ source: 'llm', say: 'On it.', actions: [], needs: null, delegate: true }), toAssistant: async () => 'All good.', ack: async () => { throw new Error('no voice'); } });
    assert.equal((await handleUtterance('check my deployments', d)).say, 'All good.');
  });
});

describe('talking to a computer that asks something back', () => {
  beforeEach(() => forgetPending());

  it('sends the request to the computer named in the sentence', async () => {
    const sent: Array<[string, string | undefined]> = [];
    const { d } = deps({ computerNames: ['Work Laptop'], toComputer: async (text, name) => (sent.push([text, name]), 'Locked.') });
    await handleUtterance('tell work laptop to lock', d);
    await handleUtterance('on my computer open youtube', d);
    assert.deepEqual(sent, [['lock', 'Work Laptop'], ['open youtube', undefined]]);
  });

  it('speaks the computer\u2019s question, and sends the answer back to the same computer, not to the cloud assistant', async () => {
    const { d, log } = deps({
      computerNames: ['Work Laptop'],
      toComputer: async (text, name) => (log.push(`computer:${text}@${name ?? ''}`), text === 'yes' ? 'Deleted.' : { reply: 'Delete 3 old images? Say yes or no.', listenAgain: true }),
    });
    const asked = await handleUtterance('on work laptop clean up docker', d);
    assert.deepEqual(asked, { ok: true, say: 'Delete 3 old images? Say yes or no.', kind: 'computer', ask: true });
    const answered = await handleUtterance('yes', d);
    assert.deepEqual(answered, { ok: true, say: 'Deleted.', kind: 'computer' });
    assert.deepEqual(log, ['computer:clean up docker@Work Laptop', 'computer:yes@Work Laptop']);
    // The question has been answered: the next "yes" is an ordinary sentence again.
    await handleUtterance('yes', d);
    assert.equal(log.at(-1), 'assistant:yes');
  });

  it('lets "stop" end it without sending anything', async () => {
    const { d, log } = deps({ toComputer: async (text) => (log.push(`computer:${text}`), { reply: 'Which folder?', listenAgain: true }) });
    await handleUtterance('on my computer find my notes', d);
    assert.deepEqual(await handleUtterance('never mind', d), { ok: true, say: 'Okay.', kind: 'stop' });
    assert.deepEqual(log, ['computer:find my notes']);
  });
});

describe('an OK asked for by voice', () => {
  beforeEach(() => forgetPending());

  function approving(answer: (allow: boolean) => Promise<string>) {
    const calls: boolean[] = [];
    const { d, log } = deps({
      toAssistant: async (t) => (log.push(`assistant:${t}`), { text: '', approval: { title: 'Delete the bucket old-logs.', detail: 'Removes 3 GB of logs', risk: 'high', answer: async (allow: boolean) => (calls.push(allow), answer(allow)) } }),
    });
    return { d, log, calls };
  }

  it('reads out what it wants to do and asks for a yes or no, instead of sending the person to the chat', async () => {
    const { d } = approving(async () => 'Deleted.');
    const r = await handleUtterance('clean up my old logs', d);
    assert.equal(r.ask, true);
    assert.match(r.say, /Delete the bucket old-logs\./);
    assert.match(r.say, /Removes 3 GB of logs/);
    assert.match(r.say, /yes or no/i);
    assert.doesNotMatch(r.say, /Open the chat/);
  });

  it('"yes" approves it and speaks what happened next', async () => {
    const { d, calls, log } = approving(async () => 'Deleted old-logs.');
    await handleUtterance('clean up my old logs', d);
    const r = await handleUtterance('yes go ahead', d);
    assert.deepEqual(calls, [true]);
    assert.deepEqual(r, { ok: true, say: 'Deleted old-logs.', kind: 'assistant' });
    assert.deepEqual(log, ['assistant:clean up my old logs']);
  });

  it('"no" refuses it', async () => {
    const { d, calls } = approving(async () => '');
    await handleUtterance('clean up my old logs', d);
    const r = await handleUtterance('no, don’t', d);
    assert.deepEqual(calls, [false]);
    assert.equal(r.ok, true);
    assert.match(r.say, /won’t/);
  });

  it('asks again when the answer is neither', async () => {
    const { d, calls } = approving(async () => 'Deleted.');
    await handleUtterance('clean up my old logs', d);
    const again = await handleUtterance('what bucket is that', d);
    assert.equal(again.ask, true);
    assert.match(again.say, /yes or no/i);
    await handleUtterance('yes', d);
    assert.deepEqual(calls, [true]);
  });

  it('speaks the server’s refusal when someone else has to approve it', async () => {
    const { d } = deps({
      toAssistant: async () => ({ text: '', approval: { title: 'Delete production', risk: 'high', answer: async () => { throw new Error('Someone else has to approve this. Ask a teammate to approve it in the chat.'); } } }),
    });
    await handleUtterance('delete production', d);
    const r = await handleUtterance('yes', d);
    assert.equal(r.ok, false);
    assert.equal(r.say, 'Someone else has to approve this. Ask a teammate to approve it in the chat.');
  });

  it('asks again when what it did next needs another OK', async () => {
    let n = 0;
    const second = { text: '', approval: { title: 'Restart the database', risk: 'normal' as const, answer: async () => 'Restarted.' } };
    const { d } = deps({ toAssistant: async () => ({ text: '', approval: { title: 'Stop the app', risk: 'normal' as const, answer: async () => (n++, second) } }) });
    await handleUtterance('fix it', d);
    const r = await handleUtterance('yes', d);
    assert.equal(r.ask, true);
    assert.match(r.say, /Restart the database/);
    assert.equal((await handleUtterance('yes', d)).say, 'Restarted.');
    assert.equal(n, 1);
  });
});


describe('yesOrNo', () => {
  it('hears yes, no, and neither, and a no wins', async () => {
    const { yesOrNo } = await import('./assistant');
    for (const t of ['yes', 'Yeah, go ahead.', 'okay do it', 'hey escanor approve it', 'sure']) assert.equal(yesOrNo(t), 'yes', t);
    for (const t of ['no', 'nope', 'don’t do that', 'cancel', 'yes, wait, no', 'not now']) assert.equal(yesOrNo(t), 'no', t);
    for (const t of ['what bucket is that', 'tell me more', '']) assert.equal(yesOrNo(t), null, t);
  });
  it('only a whole-utterance answer counts', async () => {
    const { yesOrNo } = await import('./assistant');
    for (const t of ['yes please', 'go ahead', 'ok', 'Okay, thanks']) assert.equal(yesOrNo(t), 'yes', t);
    for (const t of ['ok no', 'not now', 'yeah cancel that']) assert.equal(yesOrNo(t), 'no', t);
    for (const t of ['why does it need to be approved?', 'yes but wait', 'is that allowed', 'wait']) assert.equal(yesOrNo(t), null, t);
  });
});
