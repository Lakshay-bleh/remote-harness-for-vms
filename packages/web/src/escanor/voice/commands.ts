/**
 * What a spoken sentence means. Pure text in, a decision out: no Android, no network, so every rule here is tested.
 *
 * Where a command goes is the whole point:
 *  - things on THIS phone (open an app, call, set an alarm, torch, volume, search, a settings screen) are done by the phone;
 *  - "on my computer …" goes to the paired computer, which runs it with its own permissions and asks before anything risky;
 *  - moving around this app is done here;
 *  - everything else is a question or a task for the Escanor assistant.
 */

export type VoiceTab = 'assistant' | 'computers' | 'connections' | 'machines' | 'settings';
export type SettingsScreen = 'wifi' | 'bluetooth' | 'display' | 'sound' | 'battery' | 'apps' | 'location';

/** The buttons and gestures of the phone itself, done through Android's Accessibility permission. */
export type ControlOp = 'home' | 'back' | 'recents' | 'notifications' | 'quick_settings' | 'lock' | 'screenshot' | 'scroll_up' | 'scroll_down';

export type PhoneAction =
  | { type: 'open_app'; name: string }
  | { type: 'control'; op: ControlOp }
  | { type: 'tap_text'; text: string }
  | { type: 'type_text'; text: string }
  | { type: 'read_screen' }
  /** An app the server already chose, by its package: nothing left to match. */
  | { type: 'open_package'; package: string; label: string }
  | { type: 'open_url'; url: string }
  | { type: 'call'; who: string }
  | { type: 'alarm'; hour: number; minute: number }
  | { type: 'timer'; seconds: number }
  | { type: 'torch'; on: boolean }
  | { type: 'volume'; change: 'up' | 'down' | 'mute' | 'unmute' }
  | { type: 'web_search'; query: string }
  | { type: 'settings'; screen: SettingsScreen };

export type VoiceCommand =
  | { kind: 'phone'; action: PhoneAction }
  | { kind: 'computer'; text: string }
  | { kind: 'no_computer'; text: string }
  | { kind: 'assistant'; text: string }
  | { kind: 'go'; tab: VoiceTab }
  | { kind: 'stop' }
  | { kind: 'empty' };

export interface VoiceContext {
  /** At least one computer is paired, so "on my computer" has somewhere to go. */
  hasComputer: boolean;
}

// ---- the name
/**
 * Speech recognisers have never heard "Escanor" and spell it as they like ("escaner", "es canor", "ex canor"). Rewrite the likely
 * spellings to the name. Ordinary words (scanner, escalator, canon) are not touched.
 */
const NAME_HEARD_AS = /\be[sx]\s?c?\s?a\s?n{1,2}\s?[eo]r?\b/gi;
export const canonicalizeName = (t: string): string => t.replace(NAME_HEARD_AS, 'escanor');

/** Drop a leading "hey escanor" (or ok/hi/yo), whatever punctuation follows. */
export function stripWake(raw: string): string {
  return canonicalizeName(raw).replace(/^\s*(?:hey|ok|okay|hi|yo)\s+escanor\b[\s,.:;!?-]*/i, '').trim();
}

const clean = (t: string) => t.toLowerCase().replace(/[’']/g, "'").replace(/[.!?,]+$/g, '').replace(/\s+/g, ' ').trim();

// ---- numbers people say
const WORD_NUMBERS: Record<string, number> = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, fifteen: 15, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60 };
const numberOf = (w: string): number | null => (/^\d+$/.test(w) ? Number(w) : w in WORD_NUMBERS ? WORD_NUMBERS[w] : null);

/** "5 minutes", "1 hour 30 minutes", "half an hour", "two minutes" -> seconds. Null for nonsense or longer than a day. */
export function parseDuration(text: string): number | null {
  const t = clean(text);
  if (/^half an hour$/.test(t)) return 1800;
  if (/^(?:a )?quarter of an hour$/.test(t)) return 900;
  let total = 0;
  let found = false;
  for (const m of t.matchAll(/(\d+|[a-z]+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/g)) {
    const n = numberOf(m[1]);
    if (n === null) return null;
    const unit = m[2][0];
    total += n * (unit === 'h' ? 3600 : unit === 'm' ? 60 : 1);
    found = true;
  }
  return found && total > 0 && total <= 86_400 ? total : null;
}

/** "7 am", "7:30 pm", "18:45", "quarter past 6", "half past 9 am" -> 24-hour time. Null for nonsense. */
export function parseClock(text: string): { hour: number; minute: number } | null {
  const m = /^(?:(quarter|half) past )?(\d{1,2})(?::(\d{2}))?\s?(a\.?m\.?|p\.?m\.?)?$/.exec(clean(text));
  if (!m) return null;
  let hour = Number(m[2]);
  const minute = m[1] === 'quarter' ? 15 : m[1] === 'half' ? 30 : m[3] !== undefined ? Number(m[3]) : 0;
  const ampm = m[4]?.[0];
  if (minute > 59) return null;
  if (ampm) {
    if (hour < 1 || hour > 12) return null;
    hour = (hour % 12) + (ampm === 'p' ? 12 : 0);
  } else if (hour > 23) return null;
  return { hour, minute };
}

// ---- the sentence
const TAB_WORDS: Array<[RegExp, VoiceTab]> = [
  [/^(?:chat|assistant|the assistant|escanor)$/, 'assistant'],
  [/^computers?$/, 'computers'],
  [/^connections?$/, 'connections'],
  [/^machines?$/, 'machines'],
  [/^settings?$/, 'settings'],
];
const COMPUTER_NOUN = '(?:computer|laptop|pc|desktop|mac|machine)';
const SETTINGS_SCREENS: Record<string, SettingsScreen> = { wifi: 'wifi', 'wi-fi': 'wifi', 'wi fi': 'wifi', bluetooth: 'bluetooth', display: 'display', screen: 'display', sound: 'sound', battery: 'battery', apps: 'apps', location: 'location' };

const tabOf = (name: string): VoiceTab | null => {
  const n = name.replace(/^(?:my|the)\s+/, '');
  for (const [re, tab] of TAB_WORDS) if (re.test(n)) return tab;
  return null;
};

/** "google dot com" -> "google.com": a speech recogniser writes the word, not the dot. */
const spokenDots = (t: string): string => t.replace(/\s+dot\s+/g, '.');

const CONTROL_WORDS: Array<[RegExp, ControlOp]> = [
  [/^(?:go|take me|press|return|bring me)(?: back)?(?: to)?(?: the)? home(?: screen)?$|^home(?: screen)?$/, 'home'],
  [/^(?:go|press) back$|^back$|^navigate back$/, 'back'],
  [/^(?:show |open |press )?(?:the )?(?:recent apps|recents|app switcher|multitasking)$/, 'recents'],
  [/^(?:show |open |pull down |check )?(?:the |my )?notifications?(?: shade| panel| drawer)?$/, 'notifications'],
  [/^(?:show |open |pull down )?(?:the )?quick settings$/, 'quick_settings'],
  [/^lock(?: the| my)?(?: phone| screen)?$|^turn off the screen$/, 'lock'],
  [/^(?:take |grab )?(?:a )?screenshot$|^capture the screen$/, 'screenshot'],
  [/^scroll down(?: a bit| more)?$|^page down$/, 'scroll_down'],
  [/^scroll up(?: a bit| more)?$|^page up$/, 'scroll_up'],
];

export function parseControl(t: string): PhoneAction | null {
  for (const [re, op] of CONTROL_WORDS) if (re.test(t)) return { type: 'control', op };
  return null;
}

export function parseVoiceCommand(raw: string, ctx: VoiceContext): VoiceCommand {
  const heard = stripWake(raw);
  const t = clean(heard);
  if (!t) return { kind: 'empty' };
  if (/^(?:cancel|never ?mind|stop|stop listening|forget it|that'?s all|be quiet)$/.test(t)) return { kind: 'stop' };

  // The computer, when asked for by name.
  const toComputer =
    new RegExp(`^(?:on|in|at) my ${COMPUTER_NOUN}[, ]+(.+)$`).exec(t)?.[1] ??
    new RegExp(`^(?:tell|ask|have|get) my ${COMPUTER_NOUN}(?: to)? (.+)$`).exec(t)?.[1] ??
    new RegExp(`^(.+?) on my ${COMPUTER_NOUN}$`).exec(t)?.[1];
  if (toComputer) return ctx.hasComputer ? { kind: 'computer', text: toComputer } : { kind: 'no_computer', text: toComputer };

  // Things the phone itself does.
  const timer = /^(?:set (?:a |the )?)?timer(?: for)? (.+)$/.exec(t)?.[1];
  if (timer !== undefined) {
    const seconds = parseDuration(timer);
    if (seconds) return { kind: 'phone', action: { type: 'timer', seconds } };
  }
  const alarm = /^(?:set (?:an |the |my )?alarm (?:for|at)|wake me(?: up)? at) (.+)$/.exec(t)?.[1];
  if (alarm !== undefined) {
    const clock = parseClock(alarm);
    if (clock) return { kind: 'phone', action: { type: 'alarm', ...clock } };
  }
  const torch = /^(?:turn |switch )?(on|off)? ?(?:the )?(?:flashlight|torch)(?: (on|off))?$/.exec(t);
  if (torch && (torch[1] || torch[2])) return { kind: 'phone', action: { type: 'torch', on: (torch[1] ?? torch[2]) === 'on' } };
  const volume = /^(?:turn )?(?:the )?volume (up|down)$|^turn (?:it )?(up|down)$/.exec(t);
  if (volume) return { kind: 'phone', action: { type: 'volume', change: (volume[1] ?? volume[2]) as 'up' | 'down' } };
  if (t === 'mute' || t === 'unmute') return { kind: 'phone', action: { type: 'volume', change: t } };
  const call = /^(?:call|dial|phone|ring) (.+)$/.exec(t)?.[1];
  if (call) {
    const digits = call.replace(/[\s-]/g, '');
    return { kind: 'phone', action: { type: 'call', who: /^\+?\d{3,}$/.test(digits) ? digits : call } };
  }
  // Using the phone itself: its buttons and what is on its screen (needs the Accessibility permission, which the action explains).
  const control = parseControl(t);
  if (control) return { kind: 'phone', action: control };
  const tap = /^(?:tap|click|press|select|hit)(?: on)?(?: the)? (.+?)(?: button)?$/.exec(t)?.[1];
  if (tap) return { kind: 'phone', action: { type: 'tap_text', text: tap } };
  const typed = /^(?:type|write|enter)(?: in)? (.+)$/.exec(heard.trim().replace(/[.!?]+$/, ''))?.[1];
  if (typed) return { kind: 'phone', action: { type: 'type_text', text: typed } };
  if (/^(?:read|what(?:'s| is) on)(?: out)?(?: the| my)? screen(?: to me)?$|^what(?:'s| is) on my screen$/.test(t)) return { kind: 'phone', action: { type: 'read_screen' } };
  const site = /^(?:open|go to|visit|take me to)(?: the)? ((?:[a-z0-9-]+\.)+[a-z]{2,})(?:\/\S*)?$/.exec(spokenDots(t));
  if (site) return { kind: 'phone', action: { type: 'open_url', url: `https://${site[1]}` } };

  const search = /^(?:search(?: the web)?(?: for)?|google|look up) (.+)$/.exec(t)?.[1];
  if (search) return { kind: 'phone', action: { type: 'web_search', query: search.replace(/^(?:google|the web) (?:for )?/, '') || search } };
  const settings = /^open (wi-?fi|wi fi|bluetooth|display|screen|sound|battery|apps|location) settings$/.exec(t)?.[1];
  if (settings) return { kind: 'phone', action: { type: 'settings', screen: SETTINGS_SCREENS[settings] } };

  // Moving around this app, or opening another app.
  const verb = /^(?:go to|show|open|take me to|switch to|launch|start|run)(?: the| my)? (.+?)(?: app)?$/.exec(t);
  if (verb) {
    const tab = /^(?:go to|show|take me to|switch to)/.test(t) || /^open/.test(t) ? tabOf(verb[1]) : null;
    if (tab) return { kind: 'go', tab };
    if (/^(?:go to|show|take me to|switch to)\b/.test(t)) return { kind: 'assistant', text: heard };
    return { kind: 'phone', action: { type: 'open_app', name: verb[1] } };
  }

  return { kind: 'assistant', text: heard };
}
