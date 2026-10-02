// What the assistant may do on its own inside an Escanor worker, and what still needs a person.
//
// A managed worker is a disposable, locked-down container: its filesystem is one volume, it has no
// privileges, its network is filtered and it holds no account credentials. Inside it, working freely is
// the point -- an assistant that asks before every `ls` or test run cannot fix anything in a loop. So the
// local tools run without a card, and the card is kept for what *leaves* the sandbox:
//
//   * anything that changes a connected account (Escanor MCP calls that are not reads -- decided elsewhere);
//   * publishing work: `git push`, package publishes, calls that write to an external API;
//   * reaching outside the container's own tooling: docker, sudo, ssh, raw sockets, inline interpreters.
//
// The container, its network policy and the git proxy's protected branches are the security boundary; this
// decides when a person is *asked*. But it removes the human from the loop, so it must not be trivially
// bypassable by a prompt injection in a file, a web page or a tool result. Therefore:
//
//   * shell commands are parsed (quotes, `;`/`&&`/`|`, `$(...)`, redirections), not pattern-matched, so
//     `curl -sd @f` or `curl -sXPOST` cannot hide behind flag bundling;
//   * the command must be one we know (an allowlist of everyday development tools); anything else asks;
//   * every path is resolved through symlinks, and anything that lands outside the workspace, in a
//     credential location, or in a file that executes later (shell rc, git hooks, agent settings) asks;
//   * WebFetch is a network channel and needs an allow-listed host.
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, resolve } from 'node:path';
import { validateMcpUrl } from '@remote-harness/shared';
import { isInside, realpathLoose } from './paths.js';

export interface SandboxOptions {
  /** Where the assistant works. Edits outside it are not part of the sandbox and ask. */
  root: string;
  /** Directories the assistant may not change on its own even inside the root (the agent's own code, its data, its .env). */
  protectedPaths?: string[];
  /** Hosts WebFetch may reach without asking: exact names, or `*.example.com`. Empty = WebFetch always asks. */
  fetchAllow?: string[];
}

const WRITE_TOOLS = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit']);
const READ_PATH_TOOLS = new Set(['Read', 'Glob', 'Grep', 'LS', 'NotebookRead']);
const FREE_TOOLS = new Set(['TodoWrite', 'Task', 'Agent', 'WebSearch', 'BashOutput', 'KillShell', 'KillBash', 'ExitPlanMode']);

// ---------------------------------------------------------------- paths

// Credentials and keys. Reading these is never "everyday work", wherever they sit.
const SENSITIVE: RegExp[] = [
  /(^|\/)\.(ssh|aws|gnupg|kube|docker|claude-profiles|azure|oci)(\/|$)/,
  /(^|\/)\.config\/(gcloud|gh|hub|doctl|op)(\/|$)/,
  /(^|\/)\.credentials\.json$/,
  /(^|\/)\.(netrc|git-credentials|pgpass|pypirc|npmrc|boto)$/,
  /(^|\/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$/,
  /^\/etc\/(shadow|gshadow|sudoers|ssh)(\/|$)/,
  /^\/proc\/[^/]+\/(environ|mem|maps)$/,
  /\/dev\/(tcp|udp)\//,
];

// Files that run code later: editing them is persistent code execution, so they ask even inside the workspace.
const EXECUTES_LATER: RegExp[] = [
  /(^|\/)\.(bashrc|bash_profile|bash_login|bash_logout|profile|zshrc|zprofile|zshenv|zlogin|envrc|gitconfig)$/,
  /(^|\/)\.git\/(hooks|config)(\/|$)/,
  /(^|\/)\.(claude|husky|ssh|aws|gnupg)(\/|$)/,
  /(^|\/)\.mcp\.json$/,
  /(^|\/)\.config\/(autostart|systemd)(\/|$)/,
  /(^|\/)(crontab|authorized_keys)$/,
];

const SAFE_READ = ['/usr/', '/bin/', '/sbin/', '/lib/', '/lib64/', '/opt/', '/tmp/', '/dev/null', '/dev/stdin', '/dev/stdout', '/dev/stderr', '/etc/os-release'];
const SAFE_WRITE = ['/tmp/', '/dev/null', '/dev/stdout', '/dev/stderr'];

const expandHome = (p: string): string => (p === '~' ? homedir() : p.startsWith('~/') ? resolve(homedir(), p.slice(2)) : p);
const underAny = (real: string, prefixes: string[]): boolean => prefixes.some((p) => (p.endsWith('/') ? real.startsWith(p) || `${real}/` === p : real === p));

function realPathOf(root: string, p: string): string {
  return realpathLoose(resolve(realpathLoose(root), expandHome(p)));
}

function isProtected(real: string, opts: SandboxOptions): boolean {
  if (EXECUTES_LATER.some((re) => re.test(real))) return true;
  return (opts.protectedPaths ?? []).some((dir) => isInside(realpathLoose(dir), real));
}

/** May the assistant touch this path without asking? `mode` decides which outside-the-workspace places are fine. */
function pathAllowed(opts: SandboxOptions, p: unknown, mode: 'read' | 'write'): boolean {
  if (typeof p !== 'string' || !p) return false;
  const real = realPathOf(opts.root, p);
  if (SENSITIVE.some((re) => re.test(real) || re.test(p))) return false;
  if (mode === 'write' && isProtected(real, opts)) return false;
  if (isInside(realpathLoose(opts.root), real)) return true;
  return underAny(real, mode === 'read' ? SAFE_READ : SAFE_WRITE);
}

// ---------------------------------------------------------------- a small shell parser

type Word = { text: string; dynamic: boolean };
type Redirect = { op: string; target: Word | null };
type Simple = { words: Word[]; redirects: Redirect[]; pipedFrom: boolean };
type Parsed = { simples: Simple[]; substitutions: string[] };

// Splits a command line into simple commands. It understands quoting, `;` `&&` `||` `|` `&` and newlines, redirections, and
// finds `$(...)`, `` `...` `` and `<(...)` bodies (returned separately so they get vetted as commands too). A word that
// contains an expansion (`$X`, `${X}`, `$(...)`) is `dynamic`: its value is not known until the shell runs.
export function parseShell(src: string): Parsed {
  const simples: Simple[] = [];
  const substitutions: string[] = [];
  let words: Word[] = [];
  let redirects: Redirect[] = [];
  let pipedFrom = false;
  let cur = '';
  let curDynamic = false;
  let inWord = false;
  let pendingRedirect: string | null = null;

  const endWord = () => {
    if (!inWord) return;
    const w = { text: cur, dynamic: curDynamic };
    if (pendingRedirect !== null) {
      redirects.push({ op: pendingRedirect, target: w });
      pendingRedirect = null;
    } else {
      words.push(w);
    }
    cur = '';
    curDynamic = false;
    inWord = false;
  };
  const endSimple = (nextPiped: boolean) => {
    endWord();
    if (pendingRedirect !== null) {
      redirects.push({ op: pendingRedirect, target: null });
      pendingRedirect = null;
    }
    if (words.length > 0 || redirects.length > 0) simples.push({ words, redirects, pipedFrom });
    words = [];
    redirects = [];
    pipedFrom = nextPiped;
  };

  // Reads a balanced (...) body starting after the opening paren at index i; returns [body, indexAfterClose].
  const balanced = (i: number): [string, number] => {
    let depth = 1;
    let j = i;
    let q: string | null = null;
    for (; j < src.length; j++) {
      const c = src[j];
      if (q) {
        if (c === q) q = null;
        else if (c === '\\' && q === '"') j++;
        continue;
      }
      if (c === "'" || c === '"') q = c;
      else if (c === '\\') j++;
      else if (c === '(') depth++;
      else if (c === ')' && --depth === 0) return [src.slice(i, j), j + 1];
    }
    return [src.slice(i), src.length]; // unbalanced: take the rest
  };

  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === "'") {
      inWord = true;
      const end = src.indexOf("'", i + 1);
      const stop = end === -1 ? src.length : end;
      cur += src.slice(i + 1, stop);
      i = stop + 1;
      continue;
    }
    if (c === '"') {
      inWord = true;
      i++;
      while (i < src.length && src[i] !== '"') {
        if (src[i] === '\\' && i + 1 < src.length) {
          cur += src[i + 1];
          i += 2;
        } else if (src[i] === '$' && src[i + 1] === '(') {
          const [body, next] = balanced(i + 2);
          substitutions.push(body);
          cur += '$(…)';
          curDynamic = true;
          i = next;
        } else if (src[i] === '`') {
          const end = src.indexOf('`', i + 1);
          substitutions.push(src.slice(i + 1, end === -1 ? src.length : end));
          cur += '`…`';
          curDynamic = true;
          i = end === -1 ? src.length : end + 1;
        } else {
          if (src[i] === '$' && /[A-Za-z_{0-9@*#?!$-]/.test(src[i + 1] ?? '')) curDynamic = true;
          cur += src[i];
          i++;
        }
      }
      i++; // closing quote
      continue;
    }
    if (c === '\\') {
      inWord = true;
      if (src[i + 1] === '\n') i += 2;
      else {
        cur += src[i + 1] ?? '';
        i += 2;
      }
      continue;
    }
    if (c === '$' && src[i + 1] === '(') {
      inWord = true;
      const [body, next] = balanced(i + 2);
      substitutions.push(body);
      cur += '$(…)';
      curDynamic = true;
      i = next;
      continue;
    }
    if (c === '`') {
      inWord = true;
      const end = src.indexOf('`', i + 1);
      substitutions.push(src.slice(i + 1, end === -1 ? src.length : end));
      cur += '`…`';
      curDynamic = true;
      i = end === -1 ? src.length : end + 1;
      continue;
    }
    if (c === '$' && /[A-Za-z_{0-9@*#?!$-]/.test(src[i + 1] ?? '')) {
      inWord = true;
      curDynamic = true;
      if (src[i + 1] === '{') {
        const end = src.indexOf('}', i);
        cur += src.slice(i, end === -1 ? src.length : end + 1);
        i = end === -1 ? src.length : end + 1;
      } else {
        cur += c;
        i++;
      }
      continue;
    }
    if ((c === '<' || c === '>') && src[i + 1] === '(') {
      // process substitution: <(cmd) / >(cmd)
      inWord = true;
      const [body, next] = balanced(i + 2);
      substitutions.push(body);
      cur += `${c}(…)`;
      curDynamic = true;
      i = next;
      continue;
    }
    if (c === '>' || c === '<') {
      // a leading file descriptor ("2>") belongs to the operator, not to a word
      if (inWord && /^\d+$/.test(cur) && !curDynamic) {
        cur = '';
        inWord = false;
      } else {
        endWord();
      }
      let op = c;
      i++;
      while (i < src.length && (src[i] === c || src[i] === '&' || src[i] === '|')) op += src[i++];
      pendingRedirect = op;
      continue;
    }
    if (c === '|') {
      const double = src[i + 1] === '|';
      endSimple(!double);
      i += double ? 2 : 1;
      continue;
    }
    if (c === '&') {
      if (src[i + 1] === '&') {
        endSimple(false);
        i += 2;
      } else if (src[i + 1] === '>') {
        endWord();
        let op = '&>';
        i += 2;
        if (src[i] === '>') op += src[i++];
        pendingRedirect = op;
      } else {
        endSimple(false);
        i++;
      }
      continue;
    }
    if (c === ';' || c === '\n' || c === '(' || c === ')' || c === '{' || c === '}') {
      // `{`/`}` only separate when they stand alone (shell grouping); inside a word (e.g. brace expansion) they are text
      if ((c === '{' || c === '}') && inWord) {
        cur += c;
        i++;
        continue;
      }
      endSimple(false);
      i++;
      continue;
    }
    if (c === ' ' || c === '\t' || c === '\r') {
      endWord();
      i++;
      continue;
    }
    if (c === '#' && !inWord) {
      // comment to end of line
      while (i < src.length && src[i] !== '\n') i++;
      continue;
    }
    inWord = true;
    cur += c;
    i++;
  }
  endSimple(false);
  return { simples, substitutions };
}

// ---------------------------------------------------------------- commands

// Everyday development and inspection tools. Anything not listed (or listed under ALWAYS_ASK) asks.
const READ_TOOLS = new Set(['ls', 'pwd', 'cat', 'head', 'tail', 'wc', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'tree', 'file', 'stat', 'du', 'df', 'diff', 'cmp', 'sort', 'uniq', 'cut', 'tr', 'echo', 'printf', 'true', 'false', 'test', '[', 'expr', 'basename', 'dirname', 'realpath', 'readlink', 'date', 'which', 'whoami', 'uname', 'sleep', 'seq', 'jq', 'yq', 'md5sum', 'sha1sum', 'sha256sum', 'base64', 'xxd', 'od', 'hexdump', 'strings', 'column', 'nl', 'rev', 'tac', 'fold', 'paste', 'comm', 'join', 'less', 'more', 'cd', 'export', 'unset', 'set', 'shift', 'wait', 'nproc', 'id', 'hostname', 'type', 'command']);
const MUTATING_TOOLS = new Set(['rm', 'rmdir', 'mv', 'cp', 'mkdir', 'touch', 'chmod', 'tee', 'truncate', 'install', 'patch', 'tar', 'zip', 'unzip', 'gzip', 'gunzip', 'bzip2', 'xz']);
const DEV_TOOLS = new Set(['git', 'python', 'python3', 'pip', 'pip3', 'pytest', 'uv', 'poetry', 'node', 'npm', 'pnpm', 'yarn', 'bun', 'deno', 'tsc', 'tsx', 'eslint', 'prettier', 'jest', 'vitest', 'mocha', 'go', 'cargo', 'rustc', 'make', 'cmake', 'mvn', 'gradle', 'gradlew', 'dotnet', 'java', 'javac', 'ruby', 'bundle', 'rake', 'rspec', 'php', 'composer', 'mix', 'elixir', 'find', 'sed', 'awk', 'gawk', 'xargs', 'env', 'time', 'timeout', 'nohup', 'nice', 'curl', 'wget', 'bash', 'sh', 'zsh', 'dash']);
// Never auto-approved: raw sockets, privilege/escalation, remote shells, cloud and code-hosting CLIs, container tooling.
const ALWAYS_ASK = new Set(['nc', 'ncat', 'netcat', 'socat', 'telnet', 'ssh', 'scp', 'sftp', 'rsync', 'ftp', 'tftp', 'sudo', 'su', 'doas', 'nsenter', 'chroot', 'docker', 'podman', 'kubectl', 'helm', 'gh', 'hub', 'glab', 'aws', 'gcloud', 'az', 'doctl', 'terraform', 'pulumi', 'twine', 'gem', 'eval', 'exec', 'source', '.', 'ln', 'chown', 'dd', 'mount', 'crontab', 'at', 'systemctl', 'service', 'http', 'https', 'xh', 'aria2c', 'npx', 'pnpx', 'bunx', 'uvx', 'pipx', 'printenv', 'nmap', 'tcpdump']);
const INTERPRETERS = new Set(['python', 'python3', 'node', 'perl', 'ruby', 'php', 'lua', 'deno', 'bun', 'bash', 'sh', 'zsh', 'dash', 'ksh', 'tsx', 'ts-node', 'Rscript', 'osascript']);
const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash', 'ksh']);
// Code passed on the command line hides what runs from anyone reading the card (and from this policy).
const INLINE_CODE_FLAGS = new Set(['-c', '-e', '-E', '-p', '-r', '--eval', '--print', '--command', '-x']);
const DANGEROUS_ENV = new Set(['LD_PRELOAD', 'LD_LIBRARY_PATH', 'PATH', 'BASH_ENV', 'ENV', 'PYTHONSTARTUP', 'NODE_OPTIONS', 'GIT_SSH', 'GIT_SSH_COMMAND', 'GIT_PROXY_COMMAND', 'GIT_EXTERNAL_DIFF', 'PROMPT_COMMAND', 'IFS', 'SHELLOPTS', 'PS4']);
const TEXT_UTILS = new Set(['echo', 'printf', 'tr', 'sed', 'awk', 'gawk', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'cut', 'test', '[', 'expr', 'jq', 'sort', 'uniq']);

const SAFE_GIT_CONFIG = /^(user\.(name|email)|commit\.gpgsign|tag\.gpgsign|init\.defaultbranch|advice\.[a-z.]+|color\.[a-z.]+|pull\.rebase|fetch\.prune|merge\.ff|safe\.directory|core\.autocrlf|core\.filemode)=[^\s]*$/i;

const GIT_SUBS = new Set(['status', 'diff', 'log', 'show', 'branch', 'add', 'commit', 'checkout', 'switch', 'restore', 'stash', 'rev-parse', 'rev-list', 'ls-files', 'ls-tree', 'blame', 'grep', 'merge', 'rebase', 'cherry-pick', 'reset', 'tag', 'describe', 'shortlog', 'apply', 'am', 'mv', 'rm', 'clean', 'init', 'clone', 'fetch', 'pull', 'worktree', 'diff-tree', 'name-rev', 'cat-file', 'show-ref', 'symbolic-ref', 'for-each-ref', 'merge-base', 'reflog', 'bisect', 'format-patch', 'archive', 'gc', 'revert', 'range-diff', 'whatchanged', 'version', 'help', 'check-ignore', 'config', 'remote']);
const NPM_SUBS = new Set(['test', 't', 'tst', 'run', 'run-script', 'start', 'ci', 'install', 'i', 'add', 'remove', 'rm', 'uninstall', 'update', 'up', 'ls', 'list', 'outdated', 'audit', 'version', 'pack', 'why', 'prune', 'rebuild', 'dedupe', 'help', 'view', 'info', 'explain', 'fund', 'doctor', 'cache', 'init']);
const PIP_SUBS = new Set(['install', 'uninstall', 'list', 'show', 'freeze', 'check', 'index', 'inspect', 'debug', 'help', 'wheel', 'download', 'cache']);
const GO_SUBS = new Set(['test', 'build', 'vet', 'fmt', 'run', 'mod', 'get', 'install', 'generate', 'list', 'env', 'version', 'clean', 'doc', 'work', 'tool']);
const CARGO_SUBS = new Set(['test', 'build', 'check', 'clippy', 'fmt', 'run', 'doc', 'tree', 'add', 'remove', 'update', 'bench', 'clean', 'fetch', 'metadata', 'version', 'install', 'vendor']);

type Ctx = { opts: SandboxOptions };

const isUrl = (s: string) => /^https?:\/\//i.test(s);

// curl: a plain GET of a literal URL is allowed. Every way of *sending* something -- a body, a form, an upload, a non-GET
// method, a config file, an `@file` reference, or anything the shell expands -- asks. Short flags may be bundled (-sd, -sXPOST).
function curlAllowed(args: Word[]): boolean {
  const valueFlags = new Set(['A', 'b', 'c', 'C', 'e', 'E', 'H', 'm', 'o', 'P', 'r', 'u', 'U', 'w', 'x', 'y', 'Y', 'z', 'Z', 'X', 'd', 'F', 'T', 'K', 'Q']);
  const badShort = new Set(['d', 'F', 'T', 'K', 'Q', 'D']); // data, form, upload, config, quote, dump-header (writes anywhere)
  const badLong = new Set(['--data', '--data-raw', '--data-binary', '--data-ascii', '--data-urlencode', '--json', '--form', '--form-string', '--upload-file', '--config', '--post301', '--post302', '--post303', '--ftp-create-dirs', '--next', '--dump-header', '--trace', '--trace-ascii', '--libcurl', '--proxy-header', '--variable', '--expand-data', '--aws-sigv4']);
  const longValue = new Set(['--request', '--header', '--output', '--user-agent', '--referer', '--cookie', '--cookie-jar', '--max-time', '--connect-timeout', '--retry', '--user', '--proxy', '--output-dir', '--range', '--write-out', '--cacert', '--cert', '--key']);
  let expectValue: string | null = null;
  for (const w of args) {
    if (w.dynamic || w.text.startsWith('@')) return false;
    if (expectValue !== null) {
      if (expectValue === 'X' || expectValue === '--request') {
        if (!/^(GET|HEAD)$/i.test(w.text)) return false;
      }
      expectValue = null;
      continue;
    }
    const t = w.text;
    if (t.startsWith('--')) {
      const [name, val] = [t.split('=')[0], t.includes('=') ? t.slice(t.indexOf('=') + 1) : null];
      if (badLong.has(name)) return false;
      if (name === '--request') {
        if (val !== null) {
          if (!/^(GET|HEAD)$/i.test(val)) return false;
        } else expectValue = '--request';
      } else if (longValue.has(name) && val === null) expectValue = name;
      continue;
    }
    if (t.startsWith('-') && t.length > 1) {
      for (let k = 1; k < t.length; k++) {
        const f = t[k];
        if (badShort.has(f)) return false;
        if (valueFlags.has(f)) {
          const rest = t.slice(k + 1);
          if (f === 'X') {
            if (rest) {
              if (!/^(GET|HEAD)$/i.test(rest)) return false;
            } else expectValue = 'X';
          } else if (!rest) expectValue = f;
          break; // the rest of a cluster is this flag's value
        }
      }
      continue;
    }
    if (!isUrl(t)) return false; // a positional that is not a literal http(s) URL (file://, gopher://, a bare host...)
  }
  return expectValue === null;
}

function wgetAllowed(args: Word[]): boolean {
  const bad = new Set(['--post-data', '--post-file', '--body-data', '--body-file', '--method', '--execute', '--input-file', '--load-cookies', '--save-cookies', '--use-askpass', '--config']);
  const valueShort = new Set(['O', 'o', 'P', 't', 'T', 'w', 'U', 'Q', 'a', 'B', 'l', 'I', 'X', 'D', 'A', 'R', 'e', 'i', 'F']);
  let expectValue = false;
  for (const w of args) {
    if (w.dynamic || w.text.startsWith('@')) return false;
    if (expectValue) {
      expectValue = false;
      continue;
    }
    const t = w.text;
    if (t.startsWith('--')) {
      if (bad.has(t.split('=')[0])) return false;
      continue;
    }
    if (t.startsWith('-') && t.length > 1) {
      for (let k = 1; k < t.length; k++) {
        const f = t[k];
        if (f === 'e' || f === 'i') return false; // -e runs a .wgetrc command, -i reads URLs from a file
        if (valueShort.has(f)) {
          if (!t.slice(k + 1)) expectValue = true;
          break;
        }
      }
      continue;
    }
    if (!isUrl(t)) return false;
  }
  return !expectValue;
}

function gitAllowed(args: Word[]): boolean {
  let i = 0;
  // global options: only -C <dir> is understood; -c, --git-dir, --exec-path... can change what runs
  while (i < args.length && args[i].text.startsWith('-')) {
    const flag = args[i].text;
    if (flag === '-C') i += 2;
    else if (flag === '--no-pager' || flag === '--paginate' || flag === '-P') i += 1;
    else if (flag === '-c') {
      // `-c key=value` is how a one-off commit identity is given; only settings that cannot make git run something are accepted
      const kv = args[i + 1];
      if (!kv || kv.dynamic || !SAFE_GIT_CONFIG.test(kv.text)) return false;
      i += 2;
    } else return false;
  }
  const sub = args[i]?.text;
  if (!sub || !GIT_SUBS.has(sub)) return false;
  const rest = args.slice(i + 1).map((w) => w.text);
  if (rest.some((a) => /^(--upload-pack|--receive-pack|--exec|--ssh-command|--config|-c|--template|--separate-git-dir)(=|$)/.test(a) || a === '-u' && sub === 'clone')) return false;
  if (sub === 'remote') return rest.length === 0 || rest.every((a) => ['-v', '--verbose', 'show', 'get-url'].includes(a) || !a.startsWith('-') && rest[0] !== 'add' && rest[0] !== 'set-url' && rest[0] !== 'rename' && rest[0] !== 'remove' && rest[0] !== 'rm' && rest[0] !== 'set-head' && rest[0] !== 'prune' && rest[0] !== 'update');
  if (sub === 'config') return rest.some((a) => ['--get', '--get-all', '--list', '-l', '--get-regexp'].includes(a)) && !rest.some((a) => ['--global', '--system', '--add', '--unset', '--replace-all', '--edit', '-e'].includes(a));
  if (sub === 'archive' && rest.some((a) => a.startsWith('--remote'))) return false;
  if (sub === 'worktree' && rest[0] !== 'list' && rest[0] !== 'add' && rest[0] !== 'remove' && rest[0] !== 'prune') return false;
  if (sub === 'clone' || sub === 'fetch' || sub === 'pull') return rest.every((a) => !a.startsWith('ext::') && !a.startsWith('fd::'));
  return true;
}

function subAllowed(args: Word[], allowed: Set<string>, skipFlags = true): boolean {
  const sub = args.find((w) => !skipFlags || !w.text.startsWith('-'))?.text;
  return sub !== undefined && allowed.has(sub);
}

function interpreterAllowed(name: string, args: Word[], piped: boolean): boolean {
  if (piped) return false; // reading its program from a pipe: `curl x | sh`
  for (const w of args) {
    if (w.dynamic) return false;
    if (INLINE_CODE_FLAGS.has(w.text) || /^-[a-zA-Z]*[cepE]$/.test(w.text) && SHELLS.has(name)) return false;
    if (isUrl(w.text)) return false; // `deno run https://...`, `node https://...`
    if (w.text === '-') return false; // program from stdin
  }
  if (name === 'deno' && args[0]?.text === 'eval') return false;
  return true;
}

function sedAllowed(args: Word[]): boolean {
  // `e` executes a command and `w` writes a file the path checks cannot see
  return args.every((w) => !/(?:^|[;{}\n\s/])[we](?:\s|$|\/)/.test(w.text) && !w.text.startsWith('--in-place=') && w.text !== '-f' && !/^--file/.test(w.text));
}

function findAllowed(args: Word[]): boolean {
  return args.every((w) => !/^-(exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls|delete)$/.test(w.text));
}

function awkAllowed(args: Word[]): boolean {
  return args.every((w) => !/system\s*\(|getline|\|&|\/inet\/|\bprintf?\s*[^;]*\|\s*"/.test(w.text) && w.text !== '-f');
}

// Path-ish words to vet: anything with a slash or a leading `~`/`.`, a `key=path` value, and bare names that exist (a symlink
// in the workspace named "escape" is reached by `cat escape`, no slash needed).
function pathWords(name: string, args: Word[], opts: SandboxOptions): { word: Word; value: string }[] {
  const out: { word: Word; value: string }[] = [];
  for (const w of args) {
    let v = w.text;
    if (/^[A-Za-z_-]+=/.test(v) && v.includes('/')) v = v.slice(v.indexOf('=') + 1);
    if (v.startsWith('-') && !v.startsWith('--') && v.length > 2 && v.slice(2).includes('/')) v = v.replace(/^-[A-Za-z]/, ''); // -I/path, -o/path
    else if (v.startsWith('-')) continue;
    if (!v) continue;
    if (TEXT_UTILS.has(name) && /^\/+$/.test(v)) continue; // `tr / _`: a slash used as text
    if (isUrl(v)) continue;
    if (v.includes('/') || v.startsWith('~') || v.startsWith('.') || v === '..' || (v.length < 120 && existsSync(resolve(opts.root, v)))) out.push({ word: w, value: v });
  }
  return out;
}

function simpleAllowed(s: Simple, ctx: Ctx): boolean {
  const { opts } = ctx;
  let words = s.words;
  // leading VAR=value assignments
  while (words.length > 0 && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0].text)) {
    const name = words[0].text.slice(0, words[0].text.indexOf('='));
    if (DANGEROUS_ENV.has(name) || words[0].dynamic) return false;
    words = words.slice(1);
  }
  if (words.length === 0) return s.redirects.length === 0 || redirectsAllowed(s, ctx);

  // wrappers that run another command: vet that command instead
  for (let guard = 0; guard < 4; guard++) {
    const head = basename(words[0].text);
    if (head === 'env' || head === 'command' || head === 'nohup' || head === 'time' || head === 'nice' || head === 'timeout' || head === 'xargs') {
      let k = 1;
      while (k < words.length && (words[k].text.startsWith('-') || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k].text) || (head === 'timeout' && /^\d/.test(words[k].text)) || (head === 'nice' && /^\d/.test(words[k].text)))) {
        if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k].text) && DANGEROUS_ENV.has(words[k].text.slice(0, words[k].text.indexOf('=')))) return false;
        if (head === 'env' && (words[k].text === '-S' || words[k].text === '--split-string')) return false;
        k++;
      }
      if (k >= words.length) return head !== 'env'; // bare `env` prints the environment (secrets): ask
      words = words.slice(k);
      s = { ...s, words, pipedFrom: s.pipedFrom };
      continue;
    }
    break;
  }

  const first = words[0];
  if (first.dynamic) return false;
  const rawName = first.text;
  let name = basename(rawName);
  if (rawName.includes('/')) {
    // `./script.sh` inside the workspace is a build/test script; an absolute path must be a standard system binary
    const real = realPathOf(opts.root, rawName);
    const standard = /^\/(usr\/(local\/)?)?s?bin\//.test(real);
    if (!(isInside(realpathLoose(opts.root), real) && !isProtected(real, opts)) && !standard) return false;
    if (standard === false) name = `./${name}`; // a script of the workspace: not one of the named tools
  }
  const args = words.slice(1);
  if (ALWAYS_ASK.has(name)) return false;
  const known = READ_TOOLS.has(name) || MUTATING_TOOLS.has(name) || DEV_TOOLS.has(name) || name.startsWith('./');
  if (!known) return false;

  if (SHELLS.has(name) || INTERPRETERS.has(name)) {
    if (!interpreterAllowed(name, args, s.pipedFrom)) return false;
  } else if (s.pipedFrom && (name === 'xargs' || name === 'sudo')) {
    return false;
  }

  switch (name) {
    case 'curl':
      if (!curlAllowed(args)) return false;
      break;
    case 'wget':
      if (!wgetAllowed(args)) return false;
      break;
    case 'git':
      if (!gitAllowed(args)) return false;
      break;
    case 'npm':
    case 'pnpm':
    case 'yarn':
    case 'bun':
      if (!subAllowed(args, NPM_SUBS)) return false;
      break;
    case 'pip':
    case 'pip3':
      if (!subAllowed(args, PIP_SUBS)) return false;
      break;
    case 'uv':
      if (!subAllowed(args, new Set(['pip', 'run', 'sync', 'add', 'remove', 'lock', 'venv', 'tree', 'version']))) return false;
      break;
    case 'poetry':
      if (!subAllowed(args, new Set(['install', 'add', 'remove', 'run', 'show', 'lock', 'build', 'check', 'env', 'version']))) return false;
      break;
    case 'go':
      if (!subAllowed(args, GO_SUBS)) return false;
      break;
    case 'cargo':
      if (!subAllowed(args, CARGO_SUBS)) return false;
      break;
    case 'mvn':
    case 'gradle':
    case 'gradlew':
      if (args.some((w) => /^(deploy|publish\w*|upload\w*|release)$/.test(w.text))) return false;
      break;
    case 'composer':
    case 'bundle':
    case 'mix':
      if (args.some((w) => /^(publish|push|exec|global)$/.test(w.text))) return false;
      break;
    case 'find':
      if (!findAllowed(args)) return false;
      break;
    case 'sed':
      if (!sedAllowed(args)) return false;
      break;
    case 'awk':
    case 'gawk':
      if (!awkAllowed(args)) return false;
      break;
    case 'tar':
      if (args.some((w) => /^--(to-command|checkpoint-action|use-compress-program)/.test(w.text) || w.text === '-I')) return false;
      break;
    case 'export':
      if (args.some((w) => DANGEROUS_ENV.has(w.text.split('=')[0]))) return false;
      break;
    default:
  }

  // Paths. A word we cannot resolve (it contains an expansion) and that looks like a path cannot be vetted: ask.
  const mode = MUTATING_TOOLS.has(name) || name === 'sed' || name.startsWith('./') ? 'write' : 'read';
  const isNetworkFetch = name === 'curl' || name === 'wget';
  for (const { word, value } of pathWords(name, args, opts)) {
    if (word.dynamic && value.includes('/')) return false;
    if (isNetworkFetch) {
      // only -o/-O targets are paths here, everything else was vetted as a URL / flag value; still never a credential file
      if (!pathAllowed(opts, value, 'write')) return false;
      continue;
    }
    const wmode = name === 'cd' || name === 'pwd' ? 'read' : mode;
    if (!pathAllowed(opts, value, wmode)) return false;
  }
  for (const w of args) if (w.dynamic && /\.\.|\/dev\/|~/.test(w.text)) return false;
  return redirectsAllowed(s, ctx);
}

function redirectsAllowed(s: Simple, ctx: Ctx): boolean {
  for (const r of s.redirects) {
    if (!r.target) return false;
    if (r.target.text.startsWith('&')) continue; // 2>&1, >&2
    if (r.target.dynamic) return false;
    const writing = r.op.includes('>');
    if (!pathAllowed(ctx.opts, r.target.text, writing ? 'write' : 'read')) return false;
  }
  return true;
}

/** True when the shell command may run without a card. */
export function bashAutoAllowed(command: string, opts: SandboxOptions): boolean {
  if (!command.trim() || command.length > 20_000) return false;
  if (SENSITIVE.some((re) => re.test(command)) || /\/dev\/(tcp|udp)\//.test(command)) return false;
  const queue = [command];
  let seen = 0;
  while (queue.length > 0 && seen++ < 50) {
    const parsed = parseShell(queue.shift()!);
    queue.push(...parsed.substitutions);
    if (parsed.simples.length === 0 && !parsed.substitutions.length) return false;
    for (const s of parsed.simples) if (!simpleAllowed(s, { opts })) return false;
  }
  return seen <= 50;
}

export function commandLeavesSandbox(command: string, opts: SandboxOptions = { root: process.cwd() }): boolean {
  return !bashAutoAllowed(command, opts);
}

// ---------------------------------------------------------------- WebFetch

function fetchAllowed(input: Record<string, unknown>, opts: SandboxOptions): boolean {
  const url = input.url;
  if (typeof url !== 'string') return false;
  // Never cloud metadata or a private network, whatever the allow-list says.
  if (!validateMcpUrl(url).ok) return false;
  let host: string;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return false;
  }
  return (opts.fetchAllow ?? []).some((p) => {
    const pat = p.trim().toLowerCase();
    return pat.startsWith('*.') ? host.endsWith(pat.slice(1)) && host.length > pat.length - 1 : host === pat;
  });
}

// ---------------------------------------------------------------- entry point

/** True when the assistant may run this tool call without asking. */
export function isSandboxAutoAllowed(toolName: string, input: Record<string, unknown>, opts: SandboxOptions): boolean {
  if (FREE_TOOLS.has(toolName)) return true;
  if (toolName === 'WebFetch') return fetchAllowed(input, opts);
  if (READ_PATH_TOOLS.has(toolName)) {
    // No path means "the working directory". Any path given must be inside it (or a harmless system place), never a credential.
    const candidates: unknown[] = [input.file_path, input.notebook_path, input.path];
    if (typeof input.pattern === 'string' && toolName === 'Glob' && /^[/~]/.test(input.pattern)) candidates.push(input.pattern.split(/[*?[{]/)[0]);
    if (typeof input.glob === 'string' && /^[/~]/.test(input.glob)) candidates.push(input.glob.split(/[*?[{]/)[0]);
    return candidates.every((p) => p === undefined || p === null || p === '' ? true : pathAllowed(opts, p, 'read'));
  }
  if (WRITE_TOOLS.has(toolName)) return pathAllowed(opts, input.file_path ?? input.notebook_path ?? input.path, 'write');
  if (toolName === 'Bash') {
    const command = typeof input.command === 'string' ? input.command : '';
    return bashAutoAllowed(command, opts);
  }
  return false; // MCP tools and anything unknown are decided elsewhere, or ask
}
