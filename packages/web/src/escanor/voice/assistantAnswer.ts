import { applyMessages, emptyChat, isThinking, toDisplay, type AssistantMessages } from '@remote-harness/shared/escanor';

export interface AnswerDeps {
  fetch(after: number): Promise<AssistantMessages>;
  wait(ms: number): Promise<void>;
  now(): number;
}

/** What the assistant said back to the sentence just sent: its words, or why there are none yet. */
export interface Answer {
  text: string;
  /** It stopped to ask the person for an OK, which can only be given in the chat. */
  needsApproval: boolean;
  timedOut: boolean;
}

/**
 * After a sentence is sent to the assistant, wait until it has finished answering that sentence and return what it said. Looks for
 * the person's own sentence first (so an earlier answer in the same conversation is never mistaken for the new one), then waits
 * for the assistant to stop working.
 */
export async function waitForAnswer(deps: AnswerDeps, sent: string, o: { timeoutMs?: number; signal?: AbortSignal } = {}): Promise<Answer> {
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
    if (at >= 0) {
      const after = blocks.slice(at + 1);
      if (after.some((b) => b.type === 'approval')) return { text: '', needsApproval: true, timedOut: false };
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

/** Markdown and code are for the eye: leave them out of what is read aloud, and keep it short enough to listen to. */
export function forSpeech(markdown: string, maxChars = 420): string {
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
