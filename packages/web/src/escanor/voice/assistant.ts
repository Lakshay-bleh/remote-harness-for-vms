import { explainFailure } from '../computer/errors';
import { runPhoneAction, type DevicePlugin, type PhoneOptions } from './actions';
import { parseVoiceCommand, type VoiceTab } from './commands';

export interface AssistantDeps {
  /** The phone's native tools; null in a browser. */
  device: DevicePlugin | null;
  hasComputer: boolean;
  /** Run a sentence on the paired computer; resolves with what it said back. */
  toComputer(text: string): Promise<string>;
  /** Hand a sentence to the Escanor assistant; resolves with its answer when it has one (empty when it only started working). */
  toAssistant(text: string): Promise<string | void>;
  go(tab: VoiceTab): void;
  /** How the person wants the phone to behave (calling directly). */
  phone?: PhoneOptions;
}

export interface Reply {
  ok: boolean;
  /** What to say out loud and show. */
  say: string;
  kind?: 'phone' | 'computer' | 'assistant' | 'go' | 'stop';
  /** What the person has to turn on to make this work; voice mode shows a button for it. */
  needs?: 'accessibility';
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
export async function handleUtterance(text: string, d: AssistantDeps): Promise<Reply> {
  const cmd = parseVoiceCommand(text, { hasComputer: d.hasComputer });
  try {
    switch (cmd.kind) {
      case 'empty':
        return { ok: false, say: 'I didn’t catch that. Try again.' };
      case 'stop':
        return { ok: true, say: 'Okay.', kind: 'stop' };
      case 'phone':
        return { ...(await runPhoneAction(cmd.action, d.device, d.phone)), kind: 'phone' };
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
        const answer = await d.toAssistant(cmd.text);
        return { ok: true, say: (typeof answer === 'string' && answer.trim()) || 'Asking your Escanor assistant.', kind: 'assistant' };
      }
    }
  } catch (e) {
    return { ok: false, say: spokenProblem(e) };
  }
}
