/**
 * What an Autonomous chat never does on its own: things that cannot be undone or that hand the machine to someone else.
 *
 * The phone answers an Autonomous chat's prompts with this list (packages/mobile lib/features/machines/autonomy.dart keeps its own
 * copy, since Dart cannot import this; test/autonomy.test.ts checks the two are the same). The agent applies it itself, in a
 * PreToolUse hook, where an Autonomous chat runs in bypass mode and so asks nobody. Only a chat the person explicitly set to
 * "Bypass permissions" runs without it.
 *
 * Patterns are written exactly as the phone's raw strings, so they can be compared character for character.
 */

export type Blocked = { source: string; ignoreCase?: boolean; why: string };

/** `rm -rf` of the whole machine or a home folder. */
const RM = String.raw`\brm\s+(?:-[a-zA-Z]*[rRfF][a-zA-Z]*\s+)+(?:--no-preserve-root\s+)?(?:"?/"?|"?/\*"?|"?~/?"?|"?\$HOME/?"?|"?/(?:home|root|etc|usr|var|boot|bin|lib|opt)/?"?)(?:\s|$|;|&|\|)`;

export const BLOCKED_COMMANDS: readonly Blocked[] = [
  { source: RM, why: 'wipes the machine or a home folder' },
  { source: String.raw`\bmkfs(\.\w+)?\b`, why: 'formats a disk' },
  { source: String.raw`\bdd\b[^\n|;&]*\bof=/dev/`, why: 'writes straight onto a disk' },
  { source: String.raw`>\s*/dev/(?:sd|nvme|vd|xvd|hd)\w*`, why: 'writes straight onto a disk' },
  { source: String.raw`:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:`, why: 'a fork bomb' },
  { source: String.raw`\bchmod\s+(?:-\w+\s+)*[0-7]*777\s+/(?:\s|$)`, why: 'opens up every file on the machine' },
  { source: String.raw`\b(?:shutdown|poweroff|halt)\b|\breboot\b`, why: 'turns the machine off' },
  { source: String.raw`\bgit\s+push\b[^\n;&|]*(?:--force\b|--force-with-lease\b|\s-f\b)[^\n;&|]*\b(?:main|master|production|prod|release)\b`, why: 'force-pushes over a main branch' },
  { source: String.raw`\bgit\s+push\b[^\n;&|]*\b(?:main|master|production|prod|release)\b[^\n;&|]*(?:--force\b|--force-with-lease\b|\s-f\b)`, why: 'force-pushes over a main branch' },
  { source: String.raw`\bdrop\s+(?:database|schema)\b`, ignoreCase: true, why: 'drops a whole database' },
  { source: String.raw`\btruncate\s+table\b`, ignoreCase: true, why: 'empties a table' },
  { source: String.raw`\b(?:userdel|deluser|passwd\s+-d)\b`, why: 'changes who can log in' },
  { source: String.raw`\biptables\s+-F\b|\bufw\s+disable\b`, why: 'turns the firewall off' },
];

export const BLOCKED_PATHS: readonly Blocked[] = [
  { source: String.raw`^/(?:etc/(?:shadow|sudoers|passwd|ssh/sshd_config)|boot/|dev/|proc/|sys/)`, why: 'a system file' },
  { source: String.raw`(?:^|/)\.ssh/(?:authorized_keys|id_[a-z0-9]+)$`, why: 'who can log in' },
];

const compile = (list: readonly Blocked[]) => list.map((b) => ({ re: new RegExp(b.source, b.ignoreCase ? 'i' : ''), why: b.why }));
const COMMANDS = compile(BLOCKED_COMMANDS);
const PATHS = compile(BLOCKED_PATHS);

const FILE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit']);

/**
 * Why an Autonomous chat must not do this on its own, or null when it may. Mirrors the phone's decideAutonomously for the tools
 * that change the machine (a question for the person is handled where the prompt is answered).
 */
export function autonomousBlockReason(toolName: string, input: unknown): string | null {
  const fields = (input && typeof input === 'object' ? input : {}) as Record<string, unknown>;
  if (toolName === 'Bash') {
    const command = String(fields.command ?? '');
    for (const { re, why } of COMMANDS) if (re.test(command)) return `That ${why}.`;
    return null;
  }
  if (FILE_TOOLS.has(toolName)) {
    const path = String(fields.file_path ?? fields.notebook_path ?? '');
    for (const { re, why } of PATHS) if (re.test(path)) return `That changes ${why}.`;
  }
  return null;
}
