/**
 * Which paired computer a voice request goes to: the one named in the sentence, else the one used last, else the first. Pure, so the
 * choice is tested; the "used last" memory lives in useVoiceSession.
 */

/** A name as it is spoken: lower case, no apostrophes, punctuation as spaces ("Lakshay’s Mac-Book" -> "lakshays mac book"). */
export function spokenName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[’'`]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export const sameName = (a: string, b: string): boolean => spokenName(a) !== '' && spokenName(a) === spokenName(b);

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * A regular-expression source that finds `name` in a cleaned sentence however the recogniser punctuated it ("lakshay's macbook pro"
 * for "Lakshay’s MacBook Pro"). Null for a name too short to be told apart from ordinary words.
 */
export function namePattern(name: string): string | null {
  const words = spokenName(name).split(' ').filter(Boolean);
  if (words.join('').length < 3) return null;
  return words.map((w) => [...w].map(escape).join("'?")).join("[\\s'._-]*");
}

export interface NamedComputer {
  id: string;
  name: string;
  /** The name the person gave it on this phone, if any. */
  alias?: string;
}

export function pickComputer<T extends NamedComputer>(computers: T[], named: string | null | undefined, lastId: string | null | undefined): T | null {
  if (named) {
    const hit = computers.find((c) => (c.alias && sameName(c.alias, named)) || sameName(c.name, named));
    if (hit) return hit;
  }
  return computers.find((c) => c.id === lastId) ?? computers[0] ?? null;
}
