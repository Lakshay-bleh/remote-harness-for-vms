// What the assistant may do on its own inside an Escanor worker, and what still needs a person.
//
// A managed worker is a disposable, locked-down container: its filesystem is one volume, it has no
// privileges, its network is filtered and it holds no account credentials. Inside it, working freely is
// the point -- an assistant that asks before every `ls` or test run cannot fix anything in a loop. So the
// local tools run without a card, and the card is kept for what *leaves* the sandbox:
//
//   * anything that changes a connected account (Escanor MCP calls that are not reads -- decided elsewhere);
//   * publishing work: `git push`, package publishes, calls that write to an external API;
//   * reaching outside the container's own tooling: docker, sudo, ssh.
//
// This is a courtesy to the person (it decides when they are asked), not the security boundary: the
// container, its network policy and the git proxy's protected branches are. That is why a clever shell
// spelling that slips past these patterns still cannot push to `main` or reach another workspace.
import { isAbsolute, relative, resolve } from 'node:path';

const LOCAL_TOOLS = new Set(['Read', 'Glob', 'Grep', 'LS', 'TodoWrite', 'Task', 'Agent', 'WebFetch', 'WebSearch', 'NotebookRead', 'BashOutput', 'KillShell', 'KillBash', 'ExitPlanMode']);
const WRITE_TOOLS = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit']);

// Commands that publish work or step outside the sandbox. Matched anywhere in the command line, so
// `cd repo && git push` and `npm test; git push` are caught the same as a bare `git push`.
const LEAVES_SANDBOX: RegExp[] = [
  /\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+push\b/,
  /\bgit\b[^|;&]*\s--force\b/,
  /\bgit\s+remote\s+(?:add|set-url)\b/,
  /\bgh\s+(?:pr|issue|release|repo|workflow|api|secret)\b/,
  /\b(?:npm|pnpm|yarn)\s+publish\b/,
  /\btwine\s+upload\b/,
  /\bdocker\b/,
  /\bkubectl\b/,
  /\bsudo\b/,
  /\bssh\b|\bscp\b|\brsync\b[^|;&]*:/,
  /\b(?:curl|wget|http|https)\b[^|;&]*(?:-X\s*(?:POST|PUT|PATCH|DELETE)|--request\s*(?:POST|PUT|PATCH|DELETE)|--data|--post-data|--post-file|-d\s|--upload-file|-T\s|--form|-F\s)/i,
];

export interface SandboxOptions {
  /** Where the assistant works. Edits outside it are not part of the sandbox and ask. */
  root: string;
}

export function commandLeavesSandbox(command: string): boolean {
  return LEAVES_SANDBOX.some((re) => re.test(command));
}

function insideRoot(root: string, path: unknown): boolean {
  if (typeof path !== 'string' || !path) return false;
  const rel = relative(resolve(root), resolve(root, path));
  return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
}

/** True when the assistant may run this tool call without asking. */
export function isSandboxAutoAllowed(toolName: string, input: Record<string, unknown>, opts: SandboxOptions): boolean {
  if (LOCAL_TOOLS.has(toolName)) return true;
  if (WRITE_TOOLS.has(toolName)) return insideRoot(opts.root, input.file_path ?? input.notebook_path ?? input.path);
  if (toolName === 'Bash') {
    const command = typeof input.command === 'string' ? input.command : '';
    return command.length > 0 && !commandLeavesSandbox(command);
  }
  return false; // MCP tools and anything unknown are decided elsewhere, or ask
}
