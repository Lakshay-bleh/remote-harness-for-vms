import { applyMessages, emptyChat, isThinking, toDisplay, type AssistantItem, type AssistantMessages } from '@remote-harness/shared/escanor';
import type { AssistantTurn } from './assistant';

type ApprovalItem = Extract<AssistantItem, { kind: 'approval' }>;

export interface AnswerDeps {
  fetch(after: number): Promise<AssistantMessages>;
  wait(ms: number): Promise<void>;
  now(): number;
}

/** What the assistant said back to the sentence just sent: its words, or why there are none yet. */
export interface Answer {
  text: string;
  /** It stopped to ask the person for an OK. */
  needsApproval: boolean;
  /** What it is asking an OK for (present when `needsApproval`). */
  approval?: ApprovalItem;
  timedOut: boolean;
}

/**
 * After a sentence is sent to the assistant, wait until it has finished answering that sentence and return what it said. Looks for
 * the person's own sentence first (so an earlier answer in the same conversation is never mistaken for the new one), then waits
 * for the assistant to stop working.
 */
export async function waitForAnswer(deps: AnswerDeps, sent: string, o: { timeoutMs?: number; signal?: AbortSignal; after?: string } = {}): Promise<Answer> {
  const until = deps.now() + (o.timeoutMs ?? 90_000);
  let state = emptyChat;
  while (deps.now() < until && !o.signal?.aborted) {
    try {
      state = applyMessages(state, await deps.fetch(state.lastId));
    } catch {
      // a blip: look again
    }
    const blocks = toDisplay(state);
    let at = -1;
    blocks.forEach((b, i) => b.type === 'user' && b.text.trim() === sent.trim() && (at = i));
    // Answering an OK: only what came after that question is the new answer.
    if (at >= 0 && o.after) {
      const asked = blocks.findIndex((b, i) => i > at && b.type === 'approval' && b.item.request_id === o.after);
      if (asked >= 0) at = asked;
    }
    if (at >= 0) {
      const after = blocks.slice(at + 1);
      const ask = after.find((b) => b.type === 'approval' && b.item.status === 'pending' && b.item.request_id !== o.after);
      if (ask && ask.type === 'approval') return { text: '', needsApproval: true, approval: ask.item, timedOut: false };
      const words = after.filter((b) => b.type === 'assistant' || b.type === 'error').map((b) => (b as { text: string }).text).join('\n\n').trim();
      if (words && !state.running && !isThinking(state)) return { text: words, needsApproval: false, timedOut: false };
      // Ended with no words, only a note about the turn ("Stopped."): that is the answer, not a reason to wait on.
      const note = after.filter((b) => b.type === 'notice').at(-1);
      if (note && note.type === 'notice' && !state.running) return { text: note.text, needsApproval: false, timedOut: false };
    }
    await deps.wait(1200);
  }
  return { text: '', needsApproval: false, timedOut: !o.signal?.aborted };
}

export interface VoiceAnswerDeps extends AnswerDeps {
  /** Give the person's answer to "should I go ahead?". Its errors (a refusal from the server) are passed on as they are. */
  answer(requestId: string, allow: boolean): Promise<unknown>;
  /** Stop the turn; called when voice is cancelled while waiting. */
  stop?(): void;
}

const STILL_WORKING = 'Still working on it. The answer will be in the chat.';

/**
 * The assistant's answer for voice: its words, or the OK it is waiting for, with a way to give that OK by voice. Giving it waits
 * for what the assistant says next (which may be another question).
 */
export async function answerByVoice(deps: VoiceAnswerDeps, sent: string, o: { timeoutMs?: number; signal?: AbortSignal; after?: string } = {}): Promise<AssistantTurn> {
  const stop = () => deps.stop?.();
  o.signal?.addEventListener('abort', stop, { once: true });
  let a: Answer;
  try {
    a = await waitForAnswer(deps, sent, o);
  } finally {
    o.signal?.removeEventListener('abort', stop);
  }
  const item = a.approval;
  if (item) {
    return {
      text: '',
      approval: {
        title: item.title,
        detail: item.detail,
        risk: item.risk,
        answer: async (allow, signal) => {
          await deps.answer(item.request_id, allow);
          return answerByVoice(deps, sent, { timeoutMs: o.timeoutMs, signal, after: item.request_id });
        },
      },
    };
  }
  if (a.timedOut) return { text: STILL_WORKING };
  return { text: a.text };
}

/**
 * Markdown and code are for the eye: leave them out of what is read aloud. A long reply is spoken in pieces (speech.ts), so only a
 * really long one (more than a minute or so of listening) is cut, at a sentence, with a pointer to the chat.
 */
export function forSpeech(markdown: string, maxChars = 1500): string {
  const plain = markdown
    .replace(/```[\s\S]*?```/g, ' (some code) ')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s*/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\d+\.\s+/gm, '')
    .replace(/^\s*>\s?/gm, '')
    .replace(/[*_~|]+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (plain.length <= maxChars) return plain;
  const cut = plain.slice(0, maxChars);
  const end = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('! '), cut.lastIndexOf('? '));
  return `${end > maxChars / 2 ? cut.slice(0, end + 1) : cut.replace(/\s+\S*$/, '')} The rest is in the chat.`;
}
