import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { PartialText } from '../src/partialText.ts';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const delta = (text: string, parent: string | null = null) => ({ parent_tool_use_id: parent, event: { type: 'content_block_delta', delta: { type: 'text_delta', text } } });

describe('PartialText', () => {
  it('sends the text so far, throttled, and once more after the burst', async () => {
    const sent: string[] = [];
    const p = new PartialText((t) => sent.push(t), 50);
    p.feed(delta('Hel'));
    p.feed(delta('lo'));
    await wait(10);
    assert.deepEqual(sent, ['Hello']);
    p.feed(delta(' wor'));
    p.feed(delta('ld'));
    await wait(20);
    assert.deepEqual(sent, ['Hello'], 'not more often than every 50ms');
    await wait(60);
    assert.deepEqual(sent, ['Hello', 'Hello world']);
  });

  it('starts over at a new message and stops after reset', async () => {
    const sent: string[] = [];
    const p = new PartialText((t) => sent.push(t), 10);
    p.feed(delta('first'));
    await wait(20);
    p.feed({ parent_tool_use_id: null, event: { type: 'message_start' } } as never);
    p.feed(delta('second'));
    await wait(30);
    p.feed(delta(' more'));
    p.reset();
    await wait(30);
    assert.deepEqual(sent, ['first', 'second']);
  });

  it('ignores subagents, thinking and tool input', async () => {
    const sent: string[] = [];
    const p = new PartialText((t) => sent.push(t), 10);
    p.feed(delta('sub', 'toolu_1'));
    p.feed({ parent_tool_use_id: null, event: { type: 'content_block_delta', delta: { type: 'thinking_delta', thinking: 'hmm' } as never } });
    p.feed({ parent_tool_use_id: null, event: { type: 'content_block_delta', delta: { type: 'input_json_delta', partial_json: '{' } as never } });
    await wait(30);
    assert.deepEqual(sent, []);
  });
});
