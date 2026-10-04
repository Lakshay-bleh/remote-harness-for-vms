import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { AssistantMessages } from '@remote-harness/shared/escanor';
import { forSpeech, waitForAnswer } from './assistantAnswer';

const msg = (id: number, kind: string, extra: Record<string, unknown> = {}) => ({ id, kind, ...extra });
const page = (items: Array<ReturnType<typeof msg>>, running = false) => ({ items, approvals: [], running, pending: 0, last_id: Math.max(0, ...items.map((i) => i.id)) }) as unknown as AssistantMessages;

function clock() {
  let t = 0;
  return { now: () => t, wait: async (ms: number) => void (t += ms) };
}

describe('waitForAnswer', () => {
  it('returns what the assistant said to the sentence just sent, not an earlier answer', async () => {
    const c = clock();
    const pages: AssistantMessages[] = [
      page([msg(1, 'user', { text: 'hi' }), msg(2, 'assistant', { text: 'Hello!' })], false),
      page([msg(1, 'user', { text: 'hi' }), msg(2, 'assistant', { text: 'Hello!' }), msg(3, 'user', { text: 'status' })], true),
      page([msg(1, 'user', { text: 'hi' }), msg(2, 'assistant', { text: 'Hello!' }), msg(3, 'user', { text: 'status' }), msg(4, 'assistant', { text: 'All good.' })], false),
    ];
    let n = 0;
    const r = await waitForAnswer({ ...c, fetch: async () => pages[Math.min(n++, pages.length - 1)] }, 'status');
    assert.equal(r.text, 'All good.');
    assert.equal(r.timedOut, false);
  });

  it('gives up after the time limit with nothing, and says it timed out', async () => {
    const c = clock();
    const r = await waitForAnswer({ ...c, fetch: async () => (page([], false)) }, 'x', { timeoutMs: 5000 });
    assert.deepEqual(r, { text: '', needsApproval: false, timedOut: true });
  });

  it('stops quietly when cancelled', async () => {
    const c = clock();
    const ctl = new AbortController();
    ctl.abort();
    const r = await waitForAnswer({ ...c, fetch: async () => { throw new Error('unreachable'); } }, 'x', { signal: ctl.signal });
    assert.equal(r.timedOut, false);
  });
});

describe('forSpeech', () => {
  it('drops markdown and code, which are for the eye', () => {
    assert.equal(forSpeech('## Result\n\n- **3** services are `up`\n- see [the docs](https://x.y)\n\n```\nrm -rf /\n```'), 'Result 3 services are up see the docs (some code)');
  });
  it('shortens a long answer at a sentence and points to the chat', () => {
    const long = 'First point is here. '.repeat(40);
    const out = forSpeech(long, 100);
    assert.ok(out.length < 160);
    assert.ok(out.endsWith('The rest is in the chat.'));
    assert.ok(/point is here\. The rest/.test(out));
  });
  it('leaves a short answer alone', () => assert.equal(forSpeech('All good.'), 'All good.'));
});
