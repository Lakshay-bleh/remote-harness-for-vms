import { explainFailure } from '../computer/errors';
import { runPhoneAction, type DevicePlugin } from './actions';
import { parseVoiceCommand, type PhoneAction, type VoiceTab } from './commands';
import { planToActions, type ServerPlan } from './serverPlan';

export interface AssistantDeps {
  /** The phone's native tools; null in a browser. */
  device: DevicePlugin | null;
  hasComputer: boolean;
  /** Run a sentence on the paired computer; resolves with what it said back. */
  toComputer(text: string): Promise<string>;
  /** Hand a sentence to the Escanor assistant (opens it in the app). */
  toAssistant(text: string): Promise<void>;
  go(tab: VoiceTab): void;
  /**
   * Ask the server's brain what a sentence means (semantic match, then the AI model) and which of this phone's apps it names.
   * Resolves null when it cannot be asked (signed out, offline); never throws.
   */
  resolve?(text: string): Promise<ServerPlan | null>;
}

export interface Reply {
  ok: boolean;
  /** What to say out loud and show. */
  say: string;
  kind?: 'phone' | 'computer' | 'assistant' | 'go' | 'stop';
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
  const { actions, skipped } = planToActions(plan);
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

export async function handleUtterance(text: string, d: AssistantDeps): Promise<Reply> {
  const cmd = parseVoiceCommand(text, { hasComputer: d.hasComputer });
  try {
    switch (cmd.kind) {
      case 'empty':
        return { ok: false, say: 'I didn’t catch that. Try again.' };
      case 'stop':
        return { ok: true, say: 'Okay.', kind: 'stop' };
      case 'phone': {
        const done = { ...(await runPhoneAction(cmd.action, d.device)), kind: 'phone' as const };
        // "open <name>" that the phone's own matching could not find: the server may know the app by another name.
        if (!done.ok && cmd.action.type === 'open_app') return (await viaServer(text, d)) ?? done;
        return done;
      }
      case 'go':
        d.go(cmd.tab);
        return { ok: true, say: `Opening ${TAB_NAMES[cmd.tab]}.`, kind: 'go' };
      case 'no_computer':
        return { ok: false, say: 'You have not paired a computer yet. Open Computers in this app, then add one with the code from Escanor Desktop.' };
      case 'computer': {
        let said: string;
        try {
          said = await d.toComputer(cmd.text);
        } catch (e) {
          return { ok: false, say: spokenProblem(e) };
        }
        // A reply that is really "that is switched off" is a problem with a fix, not an answer.
        if (explainFailure(said).ask) return { ok: false, say: spokenProblem(said), kind: 'computer' };
        return { ok: true, say: said || 'Done.', kind: 'computer' };
      }
      case 'assistant': {
        const served = await viaServer(text, d);
        if (served) return served;
        await d.toAssistant(cmd.text);
        return { ok: true, say: 'Asking your Escanor assistant.', kind: 'assistant' };
      }
    }
  } catch (e) {
    return { ok: false, say: spokenProblem(e) };
  }
}
