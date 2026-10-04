/**
 * Finding the contact a person meant from what a speech recogniser heard. "tanishq usic 2027" must find "Tanishq USICT 2027": the
 * recogniser drops letters, splits numbers ("20 27"), writes words as they sound. Matching is done on the phone, on the contacts the
 * phone already has: nothing about them is sent anywhere.
 */

export interface Contact {
  name: string;
  numbers: string[];
}

export interface ContactMatch {
  contact: Contact;
  score: number;
}

const NUMBER_WORDS: Record<string, number> = { zero: 0, oh: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };

/** "twenty twenty seven" -> "2027", "two thousand and twenty seven" -> "2027", "20 27" -> "2027". Other words are left alone. */
function joinNumbers(tokens: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === 'two' && tokens[i + 1] === 'thousand') {
      let j = i + 2;
      if (tokens[j] === 'and') j++;
      let rest = 0;
      const first = NUMBER_WORDS[tokens[j]] ?? (/^\d+$/.test(tokens[j] ?? '') ? Number(tokens[j]) : null);
      if (first !== null && first <= 99) {
        rest = first;
        j++;
        const second = NUMBER_WORDS[tokens[j]];
        if (second !== undefined && second < 10 && first >= 20 && first % 10 === 0) (rest += second, j++);
      }
      out.push(String(2000 + rest));
      i = j - 1;
      continue;
    }
    // a run of 2-digit/number-word tokens that reads as a year or a number: "twenty twenty seven", "20 27"
    const n = /^\d{1,2}$/.test(t) ? Number(t) : NUMBER_WORDS[t];
    if (n !== undefined && n >= 10 && n % 10 === 0 && n <= 90 && /^[a-z]+$/.test(t) !== undefined) {
      const next = tokens[i + 1];
      const nn = next === undefined ? undefined : /^\d{1,2}$/.test(next) ? Number(next) : NUMBER_WORDS[next];
      if (nn !== undefined && (nn >= 10 || nn === undefined)) {
        // "twenty twenty": 20 20; maybe followed by a units word ("seven")
        let tail = nn;
        let consumed = 2;
        const unit = tokens[i + 2] === undefined ? undefined : NUMBER_WORDS[tokens[i + 2]];
        if (nn % 10 === 0 && unit !== undefined && unit < 10) (tail = nn + unit, consumed = 3);
        out.push(`${n}${String(tail).padStart(2, '0')}`);
        i += consumed - 1;
        continue;
      }
    }
    if (/^\d{1,2}$/.test(t) && /^\d{1,2}$/.test(tokens[i + 1] ?? '') && /^(?:19|20)$/.test(t)) {
      out.push(t + tokens[i + 1]);
      i += 1;
      continue;
    }
    out.push(NUMBER_WORDS[t] !== undefined && !/^\d/.test(t) && NUMBER_WORDS[t] < 10 ? String(NUMBER_WORDS[t]) : t);
  }
  return out;
}

/** Lowercase words and numbers, letters and digits split apart ("usict2027" -> "usict", "2027"), punctuation gone. */
export function tokens(text: string): string[] {
  const words = text
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/([a-z])(\d)/g, '$1 $2')
    .replace(/(\d)([a-z])/g, '$1 $2')
    .split(' ')
    .filter(Boolean);
  return joinNumbers(joinLetters(words)).map((w) => TITLES[w] ?? w);
}

/** Titles people say in full and phones save short (or the other way round). */
const TITLES: Record<string, string> = { doctor: 'dr', professor: 'prof', mister: 'mr', missus: 'mrs', miss: 'ms' };

/** Letters spelled out one by one ("u s i c t") are one word. A run of two or more single letters is joined. */
function joinLetters(words: string[]): string[] {
  const out: string[] = [];
  let run = '';
  const flush = () => {
    if (run) out.push(run);
    run = '';
  };
  for (const w of words) {
    if (/^[a-z]$/.test(w)) run += w;
    else (flush(), out.push(w));
  }
  flush();
  return out;
}

function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[b.length];
}

/** How a word sounds, roughly: consonants only, repeats collapsed, a few letters that sound alike merged. */
function skeleton(w: string): string {
  return w
    .replace(/ph/g, 'f')
    .replace(/[ck]+/g, 'k')
    .replace(/[sz]/g, 's')
    .replace(/[aeiouyhw]/g, '')
    .replace(/(.)\1+/g, '$1');
}

/** Likeness of two single words, 0 to 1. Numbers must be the same number; words may differ by a dropped or added letter or by sound. */
export function wordScore(heard: string, saved: string): number {
  if (heard === saved) return 1;
  const heardNumber = /^\d+$/.test(heard);
  const savedNumber = /^\d+$/.test(saved);
  if (heardNumber || savedNumber) return heardNumber && savedNumber && heard === saved ? 1 : 0;
  const edit = 1 - levenshtein(heard, saved) / Math.max(heard.length, saved.length);
  const sound = skeleton(heard) && skeleton(heard) === skeleton(saved) ? 0.88 : 0;
  // a word the recogniser cut short ("usic" for "usict"): the start matches
  const prefix = heard.length >= 3 && (saved.startsWith(heard) || heard.startsWith(saved)) ? 0.86 : 0;
  return Math.max(edit, sound, prefix);
}

/** Likeness of what was heard to one saved name: the heard words are each matched to the best unused word of the name. */
export function nameScore(heard: string[], saved: string[]): number {
  if (!heard.length || !saved.length) return 0;
  const used = new Set<number>();
  let total = 0;
  for (const h of heard) {
    let best = 0;
    let at = -1;
    saved.forEach((s, i) => {
      if (used.has(i)) return;
      const sc = wordScore(h, s);
      if (sc > best) (best = sc, (at = i));
    });
    if (at >= 0 && best >= 0.6) used.add(at);
    total += best >= 0.6 ? best : 0;
  }
  // words of the saved name that were not said count against it a little (a short query should still find a longer name)
  const unsaid = saved.length - used.size;
  return total / heard.length - Math.min(0.12, unsaid * 0.03);
}

export function rankContacts(spoken: string, contacts: Contact[]): ContactMatch[] {
  const heard = tokens(spoken);
  return contacts
    .map((contact) => ({ contact, score: nameScore(heard, tokens(contact.name)) }))
    .filter((m) => m.score > 0.5)
    .sort((a, b) => b.score - a.score);
}

export type ContactChoice = { kind: 'one'; contact: Contact } | { kind: 'ask'; options: Contact[] } | { kind: 'none' };

/** The contact meant, a short list to choose from when two fit about equally, or none. */
export function chooseContact(spoken: string, contacts: Contact[]): ContactChoice {
  const ranked = rankContacts(spoken, contacts);
  if (!ranked.length || ranked[0].score < 0.72) return ranked.length && ranked[0].score >= 0.6 ? { kind: 'ask', options: ranked.slice(0, 3).map((m) => m.contact) } : { kind: 'none' };
  const [first, second] = ranked;
  if (second && first.score - second.score < 0.08 && second.score >= 0.72) return { kind: 'ask', options: ranked.filter((m) => first.score - m.score < 0.08).slice(0, 3).map((m) => m.contact) };
  return { kind: 'one', contact: first.contact };
}
