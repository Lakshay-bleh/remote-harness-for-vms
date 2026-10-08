import { explainFailure } from '../computer/errors';
import { runPhoneAction, type DevicePlugin, type PhoneOptions } from './actions';
import { parseVoiceCommand, stripWake, type PhoneAction, type VoiceTab } from './commands';
import { chooseContact } from './contacts';
import { planToActions, type ServerPlan } from './serverPlan';

export interface AssistantDeps {
  /** The phone's native tools; null in a browser. */
  device: DevicePlugin | null;
  hasComputer: boolean;
  /** The paired computers' names, so a sentence can name one ("on Work Laptop, …"). */
  computerNames?: string[];
  /**
   * Run a sentence on a paired computer (the one named, else the one used last); resolves with what it said back, and whether it
   * asked something and is waiting for the answer.
   */
  toComputer(text: string, computer?: string): Promise<string | ComputerReply>;
  /**
   * Hand a sentence to the Escanor assistant; resolves with its answer when it has one (empty when it only started working), or with
   * the OK it is waiting for.
   */
  toAssistant(text: string): Promise<string | void | AssistantTurn>;
  /** The voice turn's signal: work started by this sentence stops when voice is cancelled. */
  signal?: AbortSignal;
  go(tab: VoiceTab): void;
  /** How the person wants the phone to behave (calling directly). */
  phone?: PhoneOptions;
  /**
   * Ask the server's brain what a sentence means (semantic match, then the AI model) and which of this phone's apps it names.
   * Resolves null when it cannot be asked (signed out, offline); never throws.
   */
  resolve?(text: string): Promise<ServerPlan | null>;
  /** Say something now, while work continues (the short acknowledgement before a task finishes). Resolves when it has been spoken. */
  ack?(text: string): Promise<void>;
  /** Show something on screen now, while work continues. */
  interim?(text: string): void;
}

/** What the assistant said back: its words, or a step it wants an OK for. */
export interface AssistantTurn {
  text: string;
  approval?: {
    title: string;
    detail?: string;
    risk?: 'normal' | 'high';
    /** Give the OK (or refuse it); resolves with what the assistant said next. Throws the server's refusal as it is. */
    answer(allow: boolean, signal?: AbortSignal): Promise<string | AssistantTurn>;
  };
}

/** What a computer said back. `listenAgain`: it asked a question, and the next sentence is the answer. */
export interface ComputerReply {
  reply: string;
  listenAgain?: boolean;
}

export interface Reply {
  ok: boolean;
  /** What to say out loud and show. */
  say: string;
  kind?: 'phone' | 'computer' | 'assistant' | 'chat' | 'go' | 'stop';
  /** What the person has to turn on to make this work; voice mode shows a button for it. */
  needs?: 'accessibility' | 'controlBuild';
  /** The reply is a question: speak it, then listen for the answer. */
  ask?: boolean;
}

const TAB_NAMES: Record<VoiceTab, string> = { assistant: 'Chat', computers: 'Computers', connections: 'Connections', machines: 'Machines', settings: 'Settings' };

/** One sentence for the ear: what is wrong, and where to fix it (this app or the computer). */
function spokenProblem(raw: unknown): string {
  const e = explainFailure(raw);
  const where = e.where === 'computer' ? 'On your computer' : e.where === 'phone' ? 'In this app' : 'On your phone and computer';
  return `${e.title}. ${where}: ${e.steps[0].replace(/^On your computer:\s*/i, '')}`;
}

/**
 * Do what was said. Returns what to say back; never throws, so the voice layer always has something to speak. Every failure names
 * where the fix is.
 */
/**
 * Ask the server about a sentence the phone's own rules did not settle, and do what it says. Returns null when the server has nothing to
 * do on the device (so the caller carries on as before), or could not be reached.
 */
async function viaServer(text: string, d: AssistantDeps): Promise<Reply | null> {
  const plan = await d.resolve?.(text).catch(() => null);
  if (!plan) return null;
  if (plan.needs === 'clarify' && plan.say) return { ok: true, say: plan.say, kind: 'phone', ask: true };
  // Small talk or a general question: the server's fast model already answered it.
  if (plan.chat && plan.say) return { ok: true, say: plan.say, kind: 'chat' };
  // A job for the full assistant: say so at once, and let it work while that is being said.
  if (plan.delegate) {
    const work = d.toAssistant(text);
    d.interim?.(plan.say);
    await Promise.race([d.ack?.(plan.say), work.then(() => undefined)]).catch(() => undefined);
    return fromAssistant(await work, plan.say || 'Asking your Escanor assistant.');
  }
  const { actions, skipped, stop } = planToActions(plan);
  if (stop && actions.length === 0) return { ok: true, say: plan.say || 'Okay.', kind: 'stop' };
  if (actions.length > 0) {
    const results: Array<{ ok: boolean; say: string }> = [];
    for (const a of actions) results.push(await runPhoneAction(a as PhoneAction, d.device));
    const bad = results.find((r) => !r.ok);
    return { ok: !bad, say: bad ? bad.say : plan.say || results[0].say, kind: 'phone' };
  }
  if (skipped > 0) return { ok: false, say: 'I understood that, but this phone cannot do it yet.', kind: 'phone' };
  if (plan.source === 'error' && plan.say) return { ok: false, say: plan.say, kind: 'phone' };
  if (plan.say && !plan.not_device) return { ok: false, say: plan.say, kind: 'phone' }; // e.g. "I couldn't find an app called X. Did you mean …?"
  return null;
}

/**
 * A question that is waiting for the next sentence: a computer asked something (the answer goes back to it, not to the cloud
 * assistant), or the assistant wants an OK (the answer is yes or no). Forgotten after two minutes, or once answered.
 */
type FollowUp = { kind: 'computer'; computer?: string; at: number } | { kind: 'approval'; approval: NonNullable<AssistantTurn['approval']>; tries: number; at: number };
let followUp: FollowUp | null = null;
const FOLLOW_UP_MS = 120_000;

/** Forget any question waiting for an answer (voice mode closed). */
export function forgetPending(): void {
  followUp = null;
  pendingChoice = null;
}

function takeFollowUp(): FollowUp | null {
  const f = followUp;
  followUp = null;
  return f && Date.now() - f.at < FOLLOW_UP_MS ? f : null;
}

/** Say a sentence to a computer and turn what it says back into a reply; a question from it makes the next sentence its answer. */
async function askComputer(text: string, computer: string | undefined, d: AssistantDeps): Promise<Reply> {
  let out: string | ComputerReply;
  try {
    out = await d.toComputer(text, computer);
  } catch (e) {
    return { ok: false, say: spokenProblem(e) };
  }
  const said = typeof out === 'string' ? out : out.reply;
  // A reply that is really "that is switched off" is a problem with a fix, not an answer.
  if (explainFailure(said).ask) return { ok: false, say: spokenProblem(said), kind: 'computer' };
  if (typeof out !== 'string' && out.listenAgain && said.trim()) {
    followUp = { kind: 'computer', computer, at: Date.now() };
    return { ok: true, say: said, kind: 'computer', ask: true };
  }
  return { ok: true, say: said || 'Done.', kind: 'computer' };
}

const NO = /\b(?:no|nope|nah|don'?t|do not|stop|cancel|deny|refuse|never ?mind|not now|negative|abort|reject|hold on|wait)\b/;
const YES = /\b(?:yes|yeah|yep|yup|go ahead|do it|approve[ds]?|allow(?: it)?|confirm(?:ed)?|proceed|go for it|please do|affirmative)\b|^(?:sure|ok|okay|alright|all right|continue|correct|right|of course|absolutely)\b/;

/** "yes", "go ahead", "no, don't": the answer to "should I go ahead?", or null when it is neither. A no wins over a yes. */
export function yesOrNo(text: string): 'yes' | 'no' | null {
  const t = stripWake(text).toLowerCase().replace(/[’']/g, "'").replace(/[.!?,]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return null;
  if (NO.test(t)) return 'no';
  return YES.test(t) ? 'yes' : null;
}

const sentence = (s: string) => {
  const t = s.trim();
  return !t ? '' : /[.!?]$/.test(t) ? t : `${t}.`;
};

/** The assistant's answer as a reply; an OK it is waiting for is read out, and the next sentence answers it. */
function fromAssistant(answer: string | void | AssistantTurn, fallback: string): Reply {
  const turn: AssistantTurn = typeof answer === 'object' && answer ? answer : { text: typeof answer === 'string' ? answer : '' };
  if (turn.approval) {
    const a = turn.approval;
    followUp = { kind: 'approval', approval: a, tries: 0, at: Date.now() };
    const say = ['Before I go on, I need your OK.', sentence(a.title), sentence(a.detail ?? ''), a.risk === 'high' ? 'This one is high impact.' : '', 'Should I go ahead? Say yes or no.'].filter(Boolean).join(' ');
    return { ok: true, say, kind: 'assistant', ask: true };
  }
  return { ok: true, say: turn.text.trim() || fallback, kind: 'assistant' };
}

async function answerApproval(f: Extract<FollowUp, { kind: 'approval' }>, text: string, d: AssistantDeps): Promise<Reply | null> {
  const yn = yesOrNo(text);
  if (!yn) {
    if (f.tries >= 1) return null; // still not an answer: treat it as a new request (the OK is still waiting in the chat)
    followUp = { ...f, tries: f.tries + 1, at: Date.now() };
    return { ok: true, say: `Should I go ahead: ${f.approval.title.trim().replace(/[.!?]+$/, '')}? Say yes or no.`, kind: 'assistant', ask: true };
  }
  try {
    const next = await f.approval.answer(yn === 'yes', d.signal);
    return fromAssistant(next, yn === 'yes' ? 'Going ahead.' : 'Okay, I won’t do that.');
  } catch (e) {
    // e.g. 409 "Someone else has to approve this…": the server's own words say what to do.
    return { ok: false, say: e instanceof Error && e.message ? e.message : 'I couldn’t send your answer. Answer it in the chat.', kind: 'assistant' };
  }
}

/** Names offered by the last "Did you mean … ?", so the next sentence can answer it. Forgotten after 40 seconds. */
let pendingChoice: { options: string[]; at: number } | null = null;
const ORDINALS: Array<[RegExp, number]> = [[/\b(?:first|1st|one)\b/, 0], [/\b(?:second|2nd|two)\b/, 1], [/\b(?:third|3rd|three)\b/, 2]];

/** If the person is answering a "Did you mean …?" (by name or "the second one"), the name they chose. */
function answerToChoice(text: string): string | null {
  const pending = pendingChoice;
  pendingChoice = null;
  if (!pending || Date.now() - pending.at > 40_000) return null;
  const lower = text.toLowerCase();
  for (const [re, i] of ORDINALS) if (re.test(lower) && pending.options[i]) return pending.options[i];
  const c = chooseContact(text, pending.options.map((name) => ({ name, numbers: [] })));
  return c.kind === 'one' ? c.contact.name : null;
}

export async function handleUtterance(text: string, d: AssistantDeps): Promise<Reply> {
  const ctx = { hasComputer: d.hasComputer, computerNames: d.computerNames };
  const waiting = takeFollowUp();
  if (waiting?.kind === 'approval') {
    const r = await answerApproval(waiting, text, d);
    if (r) return r;
  } else if (waiting) {
    const parsed = parseVoiceCommand(text, ctx);
    // The answer to a computer's question goes back to it as said; "stop" or "never mind" still ends the conversation.
    if (parsed.kind !== 'stop' && parsed.kind !== 'empty') return askComputer(stripWake(text), waiting.computer, d);
  }
  const chosen = answerToChoice(text);
  const cmd = chosen ? ({ kind: 'phone', action: { type: 'call', who: chosen } } as const) : parseVoiceCommand(text, ctx);
  try {
    switch (cmd.kind) {
      case 'empty':
        return { ok: false, say: 'I didn’t catch that. Try again.' };
      case 'stop':
        return { ok: true, say: 'Okay.', kind: 'stop' };
      case 'phone': {
        const done = { ...(await runPhoneAction(cmd.action, d.device, d.phone)), kind: 'phone' as const };
        if (done.ask && cmd.action.type === 'call') {
          const named = /^Did you mean (.+)\?$/.exec(done.say)?.[1];
          if (named) pendingChoice = { options: named.split(/, | or /), at: Date.now() };
        }
        // "open <name>" that the phone's own matching could not find: the server may know the app by another name.
        if (!done.ok && cmd.action.type === 'open_app') return (await viaServer(text, d)) ?? done;
        return done;
      }
      case 'go':
        d.go(cmd.tab);
        return { ok: true, say: `Opening ${TAB_NAMES[cmd.tab]}.`, kind: 'go' };
      case 'no_computer':
        return { ok: false, say: 'You have not paired a computer yet. Open Computers in this app, then add one with the code from Escanor Desktop.' };
      case 'computer':
        return askComputer(cmd.text, cmd.computer, d);
      case 'assistant': {
        const served = await viaServer(text, d);
        if (served) return served;
        return fromAssistant(await d.toAssistant(cmd.text), 'Asking your Escanor assistant.');
      }
    }
  } catch (e) {
    return { ok: false, say: spokenProblem(e) };
  }
}
