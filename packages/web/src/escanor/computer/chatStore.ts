/**
 * The conversations a person has had with one computer, kept on the phone so they are still there tomorrow: a list of chats, each a
 * list of turns. Pure functions over plain data (the screen decides when to save), so the rules are tested.
 */

export interface Turn {
  who: 'you' | 'computer';
  text: string;
  /** The computer's reply was a refusal: shown as an explained error with its fix, not as a bubble. */
  problem?: boolean;
  /** Names of files attached to this message. */
  files?: string[];
  at: number;
}

export interface Chat {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  turns: Turn[];
}

export const MAX_CHATS = 30;
export const MAX_TURNS = 200;
const key = (computerId: string) => `escanor.computer.chats.v1:${computerId}`;

export const newChat = (now = Date.now(), id = Math.random().toString(36).slice(2, 10)): Chat => ({ id, title: 'New chat', createdAt: now, updatedAt: now, turns: [] });

/** A chat's name: the first thing said, trimmed to a line. */
export function titleFrom(text: string): string {
  const t = text.replace(/\s+/g, ' ').trim();
  if (!t) return 'New chat';
  return t.length <= 44 ? t : `${t.slice(0, 41).trimEnd()}…`;
}

export function addTurn(chat: Chat, turn: Turn): Chat {
  const turns = [...chat.turns, turn].slice(-MAX_TURNS);
  return { ...chat, turns, updatedAt: turn.at, title: chat.turns.length === 0 && turn.who === 'you' ? titleFrom(turn.text) : chat.title };
}

/** Newest first, nothing empty (a chat nobody typed in is not worth a row), at most MAX_CHATS. */
export function tidy(chats: Chat[]): Chat[] {
  return chats
    .filter((c) => c.turns.length > 0)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, MAX_CHATS);
}

export function upsert(chats: Chat[], chat: Chat): Chat[] {
  return tidy([chat, ...chats.filter((c) => c.id !== chat.id)]);
}

export const remove = (chats: Chat[], id: string): Chat[] => chats.filter((c) => c.id !== id);

function valid(c: unknown): c is Chat {
  const x = c as Chat;
  return Boolean(x && typeof x.id === 'string' && typeof x.title === 'string' && Array.isArray(x.turns) && x.turns.every((t) => t && (t.who === 'you' || t.who === 'computer') && typeof t.text === 'string'));
}

export function loadChats(computerId: string): Chat[] {
  try {
    const raw = JSON.parse(localStorage.getItem(key(computerId)) ?? '[]');
    return Array.isArray(raw) ? tidy(raw.filter(valid)) : [];
  } catch {
    return [];
  }
}

export function saveChats(computerId: string, chats: Chat[]): void {
  try {
    localStorage.setItem(key(computerId), JSON.stringify(tidy(chats)));
  } catch {
    // storage full: the chat stays on screen for this visit
  }
}

export function forgetChats(computerId: string): void {
  try {
    localStorage.removeItem(key(computerId));
  } catch {
    // nothing to forget
  }
}

/** "Today", "Yesterday", or the date: for grouping the history list. */
export function dayLabel(at: number, now = Date.now()): string {
  const day = (t: number) => new Date(t).setHours(0, 0, 0, 0);
  const diff = Math.round((day(now) - day(at)) / 86_400_000);
  if (diff <= 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  if (diff < 7) return 'Earlier this week';
  return new Date(at).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}
