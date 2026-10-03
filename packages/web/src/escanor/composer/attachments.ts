/**
 * Things a person attaches to a message: photos, PDFs, and text or code files. This file decides what is allowed and how each kind
 * is sent. Nothing here touches the screen or the network, so the rules are tested; reading a file in the browser is `readFile`.
 */

export type AttachmentKind = 'image' | 'pdf' | 'text';

export interface Attachment {
  id: string;
  name: string;
  mime: string;
  /** Size of what will be sent, in bytes. */
  size: number;
  kind: AttachmentKind;
  /** base64 (no prefix) for images and PDFs. */
  data?: string;
  /** The words of a text or code file. */
  text?: string;
  /** A small picture to show in the message box (images only). */
  preview?: string;
}

export const LIMITS = {
  files: 4,
  /** What one image or PDF may weigh once ready to send. */
  bytesEach: 5 * 1024 * 1024,
  bytesTotal: 8 * 1024 * 1024,
  textChars: 60_000,
  /** Longest side of a photo, in pixels (bigger gains the assistant nothing and costs time). */
  imageEdge: 1568,
} as const;

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp']);
const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|jsonl|yaml|yml|toml|ini|env|log|xml|html|css|scss|js|jsx|ts|tsx|py|rb|go|rs|java|kt|swift|c|h|cpp|hpp|cs|php|sh|bash|zsh|sql|tf|dockerfile|gradle|properties|conf)$/i;

export const ACCEPT_ALL = 'image/*,application/pdf,text/*,.md,.csv,.json,.yaml,.yml,.log,.xml,.env,.toml,.sql,.sh,.py,.js,.jsx,.ts,.tsx,.go,.rs,.java,.kt,.tf';
export const ACCEPT_TEXT = 'text/*,.md,.csv,.json,.yaml,.yml,.log,.xml,.env,.toml,.sql,.sh,.py,.js,.jsx,.ts,.tsx,.go,.rs,.java,.kt,.tf';

/** What a file is, or null when Escanor cannot read it. */
export function classify(name: string, mime: string): AttachmentKind | null {
  const m = (mime || '').toLowerCase();
  if (IMAGE_TYPES.has(m)) return 'image';
  if (m.startsWith('image/')) return 'image'; // heic and friends: the browser converts them when drawing
  if (m === 'application/pdf' || /\.pdf$/i.test(name)) return 'pdf';
  if (m.startsWith('text/') || m === 'application/json' || m === 'application/xml' || TEXT_EXT.test(name)) return 'text';
  return null;
}

export const UNSUPPORTED = 'Escanor can read photos, PDFs and text or code files. Word and Excel files are not supported yet: save them as PDF first.';

export const humanSize = (n: number): string => (n < 1024 ? `${n} B` : n < 1024 * 1024 ? `${Math.round(n / 1024)} KB` : `${(n / 1024 / 1024).toFixed(1)} MB`);

/** Whether another file may be added, and if not, the sentence to show. */
export function canAdd(existing: Attachment[], next: { name: string; type: string; size: number }, allow: 'all' | 'text' = 'all'): string | null {
  const kind = classify(next.name, next.type);
  if (!kind) return UNSUPPORTED;
  if (allow === 'text' && kind !== 'text') return 'This chat takes text and code files. To send a photo or PDF, use the Escanor assistant chat.';
  if (existing.length >= LIMITS.files) return `You can attach up to ${LIMITS.files} files to one message.`;
  // photos are shrunk before sending, so only a PDF's own size counts here
  if (kind === 'pdf' && next.size > LIMITS.bytesEach) return `${next.name} is too big (${humanSize(next.size)}). The limit is ${humanSize(LIMITS.bytesEach)}.`;
  if (kind === 'text' && next.size > 2 * 1024 * 1024) return `${next.name} is too big to read as text. Attach a smaller part of it.`;
  if (existing.some((a) => a.name === next.name && a.size === next.size)) return `${next.name} is already attached.`;
  return null;
}

export function totalBytes(list: Attachment[]): number {
  return list.reduce((n, a) => n + a.size, 0);
}

/** The shape the Escanor backend takes for `attachments` on a message. */
export interface ApiAttachment {
  name: string;
  mime: string;
  kind: AttachmentKind;
  data?: string;
  text?: string;
}

export const toApi = (list: Attachment[]): ApiAttachment[] => list.map((a) => ({ name: a.name, mime: a.mime, kind: a.kind, ...(a.data ? { data: a.data } : {}), ...(a.text !== undefined ? { text: a.text } : {}) }));

/** For a chat that only takes words: put each text file's content in the message under its name. Null if it would not fit. */
export function inlineText(message: string, list: Attachment[], maxChars: number): string | null {
  const parts = [message.trim(), ...list.filter((a) => a.kind === 'text').map((a) => `[${a.name}]\n${a.text ?? ''}`)].filter(Boolean);
  const out = parts.join('\n\n');
  return out.length <= maxChars ? out : null;
}

/** A text file's words, cut to the limit (and a note when it was cut). */
export function clipText(text: string): { text: string; cut: boolean } {
  return text.length <= LIMITS.textChars ? { text, cut: false } : { text: text.slice(0, LIMITS.textChars), cut: true };
}

/** The size an image should be drawn at: the same shape, longest side at most `edge`. */
export function fitWithin(w: number, h: number, edge: number = LIMITS.imageEdge): { width: number; height: number } {
  const longest = Math.max(w, h);
  if (longest <= edge) return { width: w, height: h };
  const k = edge / longest;
  return { width: Math.max(1, Math.round(w * k)), height: Math.max(1, Math.round(h * k)) };
}

/** How a message with files reads in the chat (and on the server, which stores the same line): the words, then what was attached. */
export function withAttachmentNote(text: string, list: Array<{ name: string }>): string {
  if (!list.length) return text;
  const note = `[Attached: ${list.map((a) => a.name).join(', ')}]`;
  return text.trim() ? `${text.trim()}\n\n${note}` : note;
}
