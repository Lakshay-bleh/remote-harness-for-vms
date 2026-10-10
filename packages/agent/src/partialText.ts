// The reply as Claude writes it. The SDK streams it a few characters at a time (stream_event); sending each of those to
// the hub would be hundreds of frames a second, so the text so far is sent at most every [everyMs], and once more when
// the burst pauses. Only the main conversation's text counts: subagents and tool input stream too, but nobody reads those
// as they are typed.
import { MAX_PARTIAL_CHARS } from '@remote-harness/shared/validate';

type StreamEvent = {
  type?: string;
  delta?: { type?: string; text?: string };
};

export class PartialText {
  private text = '';
  private timer: NodeJS.Timeout | null = null;
  private lastSentAt = 0;
  private sentText = '';

  constructor(
    private readonly emit: (text: string) => void,
    private readonly everyMs = 250,
    private readonly now: () => number = Date.now,
  ) {}

  /** One SDK stream_event message. */
  feed(msg: { event?: StreamEvent; parent_tool_use_id?: string | null }): void {
    if (msg.parent_tool_use_id) return;
    const ev = msg.event;
    if (!ev) return;
    if (ev.type === 'message_start') {
      this.reset();
      return;
    }
    if (ev.type !== 'content_block_delta' || ev.delta?.type !== 'text_delta' || typeof ev.delta.text !== 'string') return;
    if (this.text.length >= MAX_PARTIAL_CHARS) return;
    this.text = (this.text + ev.delta.text).slice(0, MAX_PARTIAL_CHARS);
    this.schedule();
  }

  /** A whole message arrived (or the run ended): what was streaming is now shown for real. */
  reset(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.text = '';
    this.sentText = '';
  }

  private schedule(): void {
    if (this.timer) return;
    const wait = Math.max(0, this.lastSentAt + this.everyMs - this.now());
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, wait);
  }

  private flush(): void {
    if (!this.text || this.text === this.sentText) return;
    this.lastSentAt = this.now();
    this.sentText = this.text;
    this.emit(this.text);
  }
}
