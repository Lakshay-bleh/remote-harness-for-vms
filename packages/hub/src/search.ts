// Searching a machine's chats by what was said in them, not only by title. The database keeps each message's readable
// text (`readableText`) and narrows the candidates with a cheap substring test (`likePattern`); everything here decides
// what really matched and how well.

export type SessionSearchHit = {
  sessionId: string;
  /** One line from the best-matching message, at most SNIPPET_MAX characters, with "…" where it was cut. Empty for a title-only hit. */
  snippet: string;
  score: number;
  /** "title" when every query word is in the title, otherwise "words" (they were found in the messages). */
  match: 'title' | 'words';
};

export type SearchQuery = {
  /** Folded query words as typed, e.g. "deploying". */
  words: string[];
  /** What each word must be a prefix of, e.g. "deploy". Same order as `words`. */
  stems: string[];
  /** The folded words joined by single spaces, for the exact-phrase bonus. */
  phrase: string;
};

export const SNIPPET_MAX = 160;
const MAX_QUERY_WORDS = 8;
const MAX_WORD_LENGTH = 40;

/** Lower case without accents, so "Café" and "cafe" compare equal. */
export function fold(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

const WORD = /[\p{L}\p{N}]+/gu;

/** Turns what the user typed into words to look for, or null when there is nothing to search for. */
export function parseQuery(raw: string): SearchQuery | null {
  const words = (fold(raw.slice(0, 200)).match(WORD) ?? []).map((w) => w.slice(0, MAX_WORD_LENGTH)).slice(0, MAX_QUERY_WORDS);
  if (words.length === 0) return null;
  return { words, stems: words.map(stem), phrase: words.join(' ') };
}

// Light stemming: enough that "deployments", "deploying" and "deployed" all look for "deploy…". The result is only
// ever used as a prefix, so cutting a little too much ("created" -> "creat") is harmless.
export function stem(word: string): string {
  let w = word;
  if (w.length > 4 && w.endsWith('ies')) return w.slice(0, -3) + 'y';
  if (w.length > 4 && /(x|ch|sh|ss|z)es$/.test(w)) return w.slice(0, -2);
  if (w.length > 5 && w.endsWith('ing')) w = w.slice(0, -3);
  else if (w.length > 4 && w.endsWith('ed')) w = w.slice(0, -2);
  else if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
  else return w;
  // "running" -> "runn" -> "run", "stopped" -> "stopp" -> "stop".
  if (/([b-df-hj-np-tv-z])\1$/.test(w) && !/(ll|ss|zz|ff)$/.test(w)) w = w.slice(0, -1);
  return w;
}

// The SQL prefilter runs on the stored text, where "café" is still accented and SQLite's LIKE only ignores ASCII case.
// Letters that commonly carry accents become "_" (any one character), so the filter never drops a real match; the
// scoring below then checks properly.
export function likePattern(stemmed: string): string {
  return `%${stemmed.replace(/[aeiouycnszg]/g, '_')}%`;
}

/** The readable text of one stored message: what the user typed and what the assistant wrote. Tool calls, tool output and thinking are left out. */
export function readableText(message: unknown): string {
  const m = message as { type?: unknown; message?: { content?: unknown } } | null;
  if (!m || (m.type !== 'user' && m.type !== 'assistant')) return '';
  const content = m.message?.content;
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((b): b is { type: 'text'; text: string } => b?.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join('\n');
}

type Tokens = { folded: string[]; joined: string };

function tokens(text: string): Tokens {
  const folded = fold(text).match(WORD) ?? [];
  return { folded, joined: ` ${folded.join(' ')} ` };
}

/** Which query words appear (as a word prefix) in these tokens, and whether any appear exactly as typed. */
function wordHits(q: SearchQuery, t: Tokens): { matched: boolean[]; exact: number } {
  const matched = q.stems.map((s) => t.folded.some((w) => w.startsWith(s)));
  const exact = q.words.filter((w) => t.folded.includes(w)).length;
  return { matched, exact };
}

const hasPhrase = (q: SearchQuery, t: Tokens) => q.words.length > 1 && t.joined.includes(` ${q.phrase}`);

/** One line of `text` around the first place a query word matches, cut to SNIPPET_MAX characters. */
export function snippetFor(text: string, q: SearchQuery): string {
  const line = text.replace(/\s+/g, ' ').trim();
  if (line.length <= SNIPPET_MAX) return line;
  const words = [...line.matchAll(WORD)].map((m) => ({ at: m.index, folded: fold(m[0]) }));
  // Centre on the exact phrase when it is there, otherwise on the first word that matches.
  const phraseStart =
    q.words.length > 1 ? words.findIndex((_, i) => q.words.every((w, k) => words[i + k]?.folded === w)) : -1;
  const first = words.find((w) => q.stems.some((s) => w.folded.startsWith(s)));
  const at = phraseStart >= 0 ? words[phraseStart].at : (first?.at ?? 0);
  let start = Math.max(0, at - 40);
  if (start > 0) {
    const space = line.indexOf(' ', start);
    if (space >= 0 && space < at) start = space + 1;
  }
  const lead = start > 0 ? '…' : '';
  const room = SNIPPET_MAX - lead.length;
  if (line.length - start <= room) return lead + line.slice(start);
  let end = start + room - 1;
  const space = line.lastIndexOf(' ', end);
  if (space > at) end = space;
  return `${lead}${line.slice(start, end).trimEnd()}…`;
}

export type SearchCandidate = {
  sessionId: string;
  title: string;
  lastMessageAt: string;
  /** Readable text of this session's messages that passed the prefilter, oldest first. */
  texts: string[];
};

/**
 * Scores the candidates and returns the matches best first. A session matches when every query word is found, in its
 * title or in any of its messages. Title hits and exact phrases score higher; equal scores go to the newer session.
 */
export function rankSessions(q: SearchQuery, candidates: SearchCandidate[], limit: number): SessionSearchHit[] {
  const scored: (SessionSearchHit & { lastMessageAt: string })[] = [];
  for (const c of candidates) {
    const titleTokens = tokens(c.title);
    const title = wordHits(q, titleTokens);
    const found = [...title.matched];
    let best: { text: string; rank: number; count: number } | null = null;
    let phraseInBody = false;
    let exactInBody = 0;
    let matchingMessages = 0;
    for (let i = 0; i < c.texts.length; i++) {
      const text = c.texts[i];
      if (!text) continue;
      const t = tokens(text);
      const hits = wordHits(q, t);
      const count = hits.matched.filter(Boolean).length;
      if (count === 0) continue;
      hits.matched.forEach((m, k) => (found[k] ||= m));
      const phrase = hasPhrase(q, t);
      phraseInBody ||= phrase;
      exactInBody += hits.exact;
      matchingMessages++;
      // The snippet comes from the message that covers the most words, preferring the exact phrase, then the newest.
      const rank = count * 10 + (phrase ? 50 : 0) + hits.exact + i / (c.texts.length + 1);
      if (!best || rank >= best.rank) best = { text, rank, count };
    }
    if (!found.every(Boolean)) continue;

    const titleAll = title.matched.every(Boolean);
    let score = 0;
    if (titleAll) score += 50 + (hasPhrase(q, titleTokens) ? 20 : 0) + title.exact * 2;
    if (best) {
      score += best.count * (20 / q.words.length);
      score += phraseInBody ? 30 : 0;
      score += Math.min(exactInBody, 10) + Math.min(matchingMessages, 10);
    }
    scored.push({
      sessionId: c.sessionId,
      snippet: best ? snippetFor(best.text, q) : '',
      score: Math.round(score * 100) / 100,
      match: titleAll ? 'title' : 'words',
      lastMessageAt: c.lastMessageAt,
    });
  }
  scored.sort((a, b) => b.score - a.score || (a.lastMessageAt < b.lastMessageAt ? 1 : a.lastMessageAt > b.lastMessageAt ? -1 : 0));
  return scored.slice(0, limit).map(({ lastMessageAt: _, ...hit }) => hit);
}
