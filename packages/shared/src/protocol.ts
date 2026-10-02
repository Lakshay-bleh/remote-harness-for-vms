// Wire protocol shared by the agent (runs on each VM), the hub (the server
// you run once), and the web/PWA client. Kept as plain data types so all
// three sides can import it without pulling in the Claude Agent SDK.

export type ImageAttachment = {
  mediaType: string;
  dataBase64: string;
};

export type PermissionDecision = 'allow' | 'deny';

export type ClaudeAccount = {
  id: string;
  label: string;
};

// ---------- Agent -> Hub ----------

export type AgentHello = {
  type: 'hello';
  agentVersion: string;
  vmName: string;
  hostname: string;
  accounts: ClaudeAccount[];
  sessions: AgentSessionSummary[];
};

export type AgentSessionSummary = {
  sessionId: string;
  cwd: string;
  title: string;
  createdAt: string;
  status: 'active' | 'idle';
  accountId: string;
};

export type AgentSdkMessage = {
  type: 'sdk_message';
  sessionId: string;
  tempId?: string;
  message: unknown; // raw SDKMessage from @anthropic-ai/claude-agent-sdk
};

export type AgentSessionCreated = {
  type: 'session_created';
  tempId: string;
  sessionId: string;
  cwd: string;
  title: string;
  accountId: string;
};

export type AgentSessionEnded = {
  type: 'session_ended';
  sessionId: string;
  reason?: string;
};

export type AgentPermissionRequest = {
  type: 'permission_request';
  sessionId: string;
  requestId: string;
  toolName: string;
  input: Record<string, unknown>;
  blockedPath?: string;
};

export type AgentError = {
  type: 'error';
  sessionId?: string;
  tempId?: string;
  message: string;
};

export type AgentProjectsList = {
  type: 'projects_list';
  requestId: string;
  projects: string[]; // relative paths under the agent's workspace root
};

export type AgentMcpServerStatus = {
  name: string;
  // 'configured' = accepted and will be used by the next session; the others are what a
  // live session's own MCP client reported when it dialled the server.
  status: 'configured' | 'connected' | 'pending' | 'needs-auth' | 'failed' | 'disabled';
  error?: string;
};

export type AgentMcpStatus = {
  type: 'mcp_status';
  servers: AgentMcpServerStatus[];
  liveSessions: number; // sessions the change was applied to without a restart
};

export type AgentToHubMessage =
  | AgentHello
  | AgentSdkMessage
  | AgentSessionCreated
  | AgentSessionEnded
  | AgentPermissionRequest
  | AgentError
  | AgentProjectsList
  | AgentMcpStatus;

// ---------- Hub -> Agent ----------

export type HubUserInput = {
  type: 'user_input';
  sessionId: string; // real session id, or the tempId for a brand-new chat
  tempId?: string; // set only when sessionId is a not-yet-created chat
  cwd?: string; // used only when starting/resuming a session
  accountId?: string; // used only when starting a brand-new session
  text: string;
  images?: ImageAttachment[];
};

export type HubInterrupt = {
  type: 'interrupt';
  sessionId: string;
};

export type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'dontAsk' | 'auto';

export type EffortLevel = 'low' | 'medium' | 'high' | 'xhigh' | 'max';

export type HubSetPermissionMode = {
  type: 'set_permission_mode';
  sessionId: string;
  mode: PermissionMode;
};

export type HubSetModel = {
  type: 'set_model';
  sessionId: string;
  model?: string;
};

export type HubSetEffort = {
  type: 'set_effort';
  sessionId: string;
  effort: EffortLevel | null;
};

export type HubPermissionResponse = {
  type: 'permission_response';
  requestId: string;
  behavior: PermissionDecision;
  message?: string;
};

export type HubListProjects = {
  type: 'list_projects';
  requestId: string;
};

// An MCP server the hub keeps installed on every VM. `name` becomes the server's namespace
// in Claude Code (`mcp__<name>__<tool>`), so it is restricted to characters that survive that.
export type ManagedMcpServer = {
  name: string;
  url: string; // streamable-HTTP endpoint
  headers?: Record<string, string>; // e.g. { Authorization: 'Bearer ...' }
  autoAllow?: boolean; // pre-approve ALL of this server's tools so chats never stall on a permission card
  // When autoAllow is off: still pre-approve the calls that only *read* (see isReadOnlyMcpCall), so a
  // chat can look things up freely and asks only before it changes something.
  autoAllowReads?: boolean;
  // When autoAllow is off: also pre-approve `escanor_invoke` calls whose tool_id is one of these (exact, or a
  // trailing `*` prefix). This is how an operator's playbook lets a machine post in a channel or open a ticket
  // without a card, while everything else that changes something still waits for a person.
  autoAllowTools?: string[];
  alwaysLoad?: boolean; // load its tools into every prompt instead of deferring them behind tool search
  managedBy?: string; // who installed it ('escanor'); informational
  updatedAt: string;
};

// Declarative: always the complete set. The agent makes its sessions match it, so a server
// missing from the list is removed and a VM that was offline converges as soon as it is back.
export type HubSetMcpServers = {
  type: 'set_mcp_servers';
  servers: ManagedMcpServer[];
};

export type HubToAgentMessage =
  | HubUserInput
  | HubInterrupt
  | HubSetPermissionMode
  | HubSetModel
  | HubSetEffort
  | HubPermissionResponse
  | HubListProjects
  | HubSetMcpServers;

// ---------- Hub -> Browser (push channel) ----------

export type BrowserVmStatus = {
  type: 'vm_status';
  vmId: string;
  name: string;
  connected: boolean;
  accounts: ClaudeAccount[];
};

export type BrowserSdkMessage = {
  type: 'sdk_message';
  vmId: string;
  sessionId: string;
  tempId?: string;
  message: unknown;
  createdAt: string;
};

export type BrowserSessionCreated = {
  type: 'session_created';
  vmId: string;
  tempId: string;
  sessionId: string;
  cwd: string;
  title: string;
  accountId: string;
};

export type BrowserSessionEnded = {
  type: 'session_ended';
  vmId: string;
  sessionId: string;
};

export type BrowserPermissionRequest = {
  type: 'permission_request';
  vmId: string;
  sessionId: string;
  requestId: string;
  toolName: string;
  input: Record<string, unknown>;
  blockedPath?: string;
};

export type BrowserPermissionResolved = {
  type: 'permission_resolved';
  vmId: string;
  sessionId: string;
  requestId: string;
};

export type HubToBrowserMessage =
  | BrowserVmStatus
  | BrowserSdkMessage
  | BrowserSessionCreated
  | BrowserSessionEnded
  | BrowserPermissionRequest
  | BrowserPermissionResolved;

// ---------- REST DTOs ----------

export type VmDto = {
  id: string;
  name: string;
  connected: boolean;
  lastSeenAt: string | null;
  accounts: ClaudeAccount[];
};

export type SessionDto = {
  id: string;
  vmId: string;
  cwd: string;
  title: string;
  createdAt: string;
  lastMessageAt: string;
  status: 'active' | 'idle' | 'ended';
  accountId: string;
};

export type MessageDto = {
  id: number;
  sessionId: string;
  vmId: string;
  message: unknown;
  createdAt: string;
};

export type McpServerDto = Omit<ManagedMcpServer, 'headers'> & {
  // Header *names* only. Values are credentials and never leave the hub once stored.
  headerNames: string[];
};

export type McpServerInput = {
  url: string;
  headers?: Record<string, string>;
  autoAllow?: boolean;
  alwaysLoad?: boolean;
  managedBy?: string;
};

// The first agent release that understands `set_mcp_servers`. An older agent ignores the message
// without saying so, so the hub reports it as needing an update instead of "installing" forever.
export const MIN_MCP_AGENT_VERSION = '0.3.0';

export function agentSupportsMcp(version: string | null | undefined): boolean {
  if (!version) return false;
  const parse = (v: string) => v.split('.').map((n) => parseInt(n, 10) || 0);
  const have = parse(version);
  const need = parse(MIN_MCP_AGENT_VERSION);
  for (let i = 0; i < Math.max(have.length, need.length); i++) {
    const d = (have[i] ?? 0) - (need[i] ?? 0);
    if (d !== 0) return d > 0;
  }
  return true;
}

export type VmMcpStatusDto = {
  vmId: string;
  name: string;
  connected: boolean;
  agentVersion: string | null;
  mcpSupported: boolean;
  reportedAt: string | null;
  servers: AgentMcpServerStatus[];
  liveSessions: number;
};

export type McpOverviewDto = {
  servers: McpServerDto[];
  vms: VmMcpStatusDto[];
};

export type McpPutResultDto = {
  server: McpServerDto;
  vmsConnected: number;
  vmsTotal: number;
};

export const MCP_SERVER_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,31}$/;

// Claude Code names a server's tools `mcp__<server>__<tool>`. A server called "a__b" would be indistinguishable from
// tool "b__..." of server "a", so a name with "__" could inherit another server's approvals: refuse it.
export const isValidMcpServerName = (name: string): boolean => MCP_SERVER_NAME_RE.test(name) && !name.includes('__');

// ---------- outbound MCP URL (SSRF guard) ----------

function ipv4(host: string): number[] | null {
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return null;
  const p = m.slice(1).map(Number);
  return p.every((n) => n <= 255) ? p : null;
}

// Expands ::ffff:7f00:1 style IPv4-mapped addresses (what URL parsing produces) to dotted quads.
function mappedIpv4(host: string): number[] | null {
  const m = host.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
  if (!m) return null;
  const hi = parseInt(m[1], 16);
  const lo = parseInt(m[2], 16);
  return [hi >> 8, hi & 255, lo >> 8, lo & 255];
}

function classifyHost(rawHost: string): 'metadata' | 'private' | 'public' {
  const host = rawHost.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.$/, '');
  if (host === 'metadata.google.internal' || host === 'metadata' || host.endsWith('.metadata.google.internal')) return 'metadata';
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.internal') || host.endsWith('.local')) return 'private';

  const v4 = ipv4(host) ?? mappedIpv4(host);
  if (v4) {
    const [a, b] = v4;
    if (a === 169 && b === 254) return 'metadata';
    if (a === 0 || a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127)) return 'private';
    return 'public';
  }
  if (host.includes(':')) {
    if (host === '::1' || host === '::') return 'private';
    if (/^fe[89ab]/.test(host) || host.startsWith('fd00:ec2:')) return 'metadata'; // link-local, AWS IPv6 IMDS
    if (/^f[cd]/.test(host)) return 'private'; // unique-local
  }
  return 'public';
}

// The hub pushes this URL (plus a bearer token) to every VM, so it must not be pointable
// at cloud metadata endpoints or, by default, anything on a private network.
export function validateMcpUrl(url: unknown, opts: { allowPrivate?: boolean } = {}): { ok: true; value: string } | { ok: false; error: string } {
  if (!typeof url === 'string' || url.length > 2048) return { ok: false, error: 'url required' };
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return { ok: false, error: 'invalid url' };
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return { ok: false, error: 'url must be http(s)' };
  if (u.username || u.password) return { ok: false, error: 'url must not embed credentials' };
  const kind = classifyHost(u.hostname);
  if (kind === 'metadata') return { ok: false, error: 'url points at a link-local / metadata address' };
  if (kind === 'private' && !opts.allowPrivate) return { ok: false, error: 'url points at a private or loopback address' };
  return { ok: true, value: u.toString() };
}


// ---------- MCP server helpers (pure; used by the Node hub and the Worker hub alike) ----------

const HEADER_NAME_RE = /^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,64}$/;
const MAX_HEADERS = 16;
const MAX_HEADER_VALUE = 4096;

export type ParsedMcpServerInput = { ok: true; server: Omit<ManagedMcpServer, 'updatedAt'> } | { ok: false; error: string };

export type ParseMcpOptions = {
  /** The entry being updated. Fields the request leaves out keep its values, so a partial update cannot reset them. */
  existing?: ManagedMcpServer;
  /** Accept loopback / private-network URLs (a hub that runs beside its MCP server). Metadata addresses never pass. */
  allowPrivate?: boolean;
};

export function parseMcpServerInput(name: string, body: unknown, opts: ParseMcpOptions = {}): ParsedMcpServerInput {
  if (!isValidMcpServerName(name)) {
    return { ok: false, error: 'Server name must be 1-32 chars of a-z, 0-9, "_" or "-", starting with a letter or digit, and must not contain "__"' };
  }
  const b = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const existing = opts.existing;

  if (typeof b.url !== 'string') return { ok: false, error: 'url is required' };
  const checked = validateMcpUrl(b.url.trim(), { allowPrivate: opts.allowPrivate });
  if (!checked.ok) return { ok: false, error: checked.error };

  let headers: Record<string, string> | undefined = existing?.headers;
  if (b.headers !== undefined) {
    headers = undefined;
    if (b.headers !== null) {
      if (typeof b.headers !== 'object' || Array.isArray(b.headers)) return { ok: false, error: 'headers must be an object' };
      const entries = Object.entries(b.headers as Record<string, unknown>);
      if (entries.length > MAX_HEADERS) return { ok: false, error: `at most ${MAX_HEADERS} headers` };
      headers = {};
      for (const [k, v] of entries) {
        if (!HEADER_NAME_RE.test(k)) return { ok: false, error: `invalid header name "${k}"` };
        // A CR/LF in a value would let a caller smuggle extra headers into every MCP request.
        if (typeof v !== 'string' || v.length > MAX_HEADER_VALUE || /[\r\n]/.test(v)) {
          return { ok: false, error: `invalid value for header "${k}"` };
        }
        headers[k] = v;
      }
    }
  }

  // A flag is a boolean or absent. Coercing (Boolean("false") === true) turned a string into blanket approval.
  const flag = (key: 'autoAllow' | 'autoAllowReads' | 'alwaysLoad', fallback: boolean): boolean | null => {
    const v = b[key];
    if (v === undefined) return existing?.[key] ?? fallback;
    return typeof v === 'boolean' ? v : null;
  };
  // Approving every tool of a server is something an operator asks for; a new server starts out asking.
  const autoAllow = flag('autoAllow', false);
  const autoAllowReads = flag('autoAllowReads', false);
  const alwaysLoad = flag('alwaysLoad', true);
  for (const [key, val] of [['autoAllow', autoAllow], ['autoAllowReads', autoAllowReads], ['alwaysLoad', alwaysLoad]] as const) {
    if (val === null) return { ok: false, error: `${key} must be true or false` };
  }

  return {
    ok: true,
    server: {
      name,
      url: checked.value,
      headers,
      autoAllow: autoAllow as boolean,
      autoAllowReads: autoAllowReads as boolean,
      ...(existing?.autoAllowTools ? { autoAllowTools: existing.autoAllowTools } : {}),
      alwaysLoad: alwaysLoad as boolean,
      managedBy: typeof b.managedBy === 'string' ? b.managedBy.slice(0, 32) : existing?.managedBy,
    },
  };
}

export function toMcpServerDto(s: ManagedMcpServer): McpServerDto {
  const { headers, ...rest } = s;
  return { ...rest, headerNames: Object.keys(headers ?? {}) };
}

// A token issued for one purpose (Escanor's integration), separate from a browser login so that
// signing out never breaks it and it can be revoked on its own. The value is shown once, on creation.
export type ApiTokenDto = { id: string; label: string; createdAt: string };
export type ApiTokenCreatedDto = ApiTokenDto & { token: string };

// ---------- Is this MCP call read-only? ----------
//
// Used to let a chat look things up without asking while still asking before it changes anything.
// The rule is deliberately one-sided: a call is "read" only if it positively looks like one, and
// anything unrecognised, mixed ("get_or_create"), or touching secrets is *not* -- it asks. A wrong
// "no" costs one click; a wrong "yes" changes someone's cloud account without asking.

const READ_VERBS = new Set([
  'list', 'get', 'describe', 'read', 'search', 'query', 'status', 'show', 'find', 'count', 'fetch',
  'view', 'head', 'check', 'lookup', 'inspect', 'retrieve', 'summary', 'overview', 'stats', 'usage',
  'providers', 'tools', 'whoami', 'me',
]);

const CHANGE_WORDS = new Set([
  'create', 'delete', 'remove', 'update', 'put', 'post', 'patch', 'set', 'add', 'start', 'stop', 'restart',
  'reboot', 'terminate', 'destroy', 'deploy', 'apply', 'run', 'exec', 'execute', 'invoke', 'send', 'write',
  'upload', 'attach', 'detach', 'revoke', 'rotate', 'reset', 'cancel', 'scale', 'resize', 'merge', 'close',
  'open', 'push', 'publish', 'import', 'restore', 'enable', 'disable', 'grant', 'invite', 'transfer',
  'drain', 'kill', 'purge', 'clear', 'flush', 'trigger', 'rollback', 'promote', 'assign', 'unassign',
  'register', 'deregister', 'subscribe', 'unsubscribe', 'approve', 'reject', 'commit', 'fork', 'clone',
  'archive', 'unarchive', 'lock', 'unlock', 'move', 'rename', 'copy', 'sync', 'schedule', 'submit',
  'suspend', 'resume', 'pause', 'replace', 'modify', 'edit', 'change', 'confirm', 'pay', 'refund', 'charge',
  // A read verb in front of one of these still ends in a change: list_and_drop_tables, get_and_notify, fetch_and_install.
  'drop', 'wipe', 'erase', 'truncate', 'shred', 'format', 'notify', 'alert', 'page', 'email', 'mail', 'message', 'text', 'tweet',
  'share', 'broadcast', 'install', 'uninstall', 'download', 'mount', 'unmount', 'shutdown', 'poweroff', 'power', 'wake',
  'evict', 'expire', 'invalidate', 'renew', 'reissue', 'regenerate', 'issue', 'mint', 'sign', 'encrypt', 'decrypt', 'ban', 'kick',
  'mute', 'unmute', 'block', 'unblock', 'pin', 'unpin', 'star', 'unstar', 'follow', 'unfollow', 'vote', 'comment', 'reply', 'react',
  'insert', 'upsert', 'alter', 'grant', 'call', 'ping', 'dispatch', 'emit', 'publish', 'cast', 'bump', 'increment', 'decrement',
]);

// Words that join two operations ("list and drop"). A call that does more than one thing is not a plain read.
const CONNECTOR_WORDS = new Set(['and', 'then', 'or', 'also', 'after', 'before', 'plus', 'with', 'via', 'else', 'while', 'until']);

// A SQL statement or GraphQL operation that changes data, found anywhere in the arguments.
const WRITE_IN_ARGS = /\b(?:insert|update|delete|drop|alter|truncate|create|grant|revoke|merge|replace|upsert|rename|vacuum|reindex|copy|call|exec|execute|attach|detach|pragma|mutation)\b/i;

function argsContainWrite(value: unknown, depth = 0, budget = { left: 200_000 }): boolean {
  if (depth > 12 || budget.left <= 0) return true; // too deep / too big to vet: ask
  if (typeof value === 'string') {
    budget.left -= value.length;
    return WRITE_IN_ARGS.test(value);
  }
  if (Array.isArray(value)) return value.some((v) => argsContainWrite(v, depth + 1, budget));
  if (value && typeof value === 'object') return Object.values(value as Record<string, unknown>).some((v) => argsContainWrite(v, depth + 1, budget));
  return false;
}

// Reading these is itself sensitive; a person should see the request first.
const SENSITIVE_WORDS = new Set(['secret', 'secrets', 'password', 'passwords', 'credential', 'credentials', 'token', 'tokens', 'key', 'keys', 'apikey', 'apikeys', 'private', 'ssh', 'cert', 'certificate', 'certificates', 'env', 'vault']);

// The tools Escanor's MCP server exposes for discovery. They never change anything.
const ESCANOR_READ_ONLY_TOOLS = new Set(['escanor_list_providers', 'escanor_connection_status', 'escanor_list_tools', 'escanor_usage_stats']);

// Exact id, or a prefix when the pattern ends in `*` (and has something before it). Anything else does not match.
export function mcpToolIdMatches(patterns: readonly string[] | undefined, toolId: string): boolean {
  if (!toolId || !patterns) return false;
  return patterns.some((p) => (p.length > 1 && p.endsWith('*') ? toolId.startsWith(p.slice(0, -1)) : p === toolId));
}

export function isReadOnlyMcpCall(tool: string, input: Record<string, unknown> | undefined): boolean {
  if (ESCANOR_READ_ONLY_TOOLS.has(tool)) return true;
  if (tool !== 'escanor_invoke') return false;

  const toolId = typeof input?.tool_id === 'string' ? input.tool_id : '';
  if (!toolId) return false;
  const args = input?.arguments;
  // An explicit confirm flag is how Escanor marks a destructive call; its presence means the caller
  // knew it was one.
  if (args && typeof args === 'object' && (args as Record<string, unknown>).confirm) return false;

  const words = toolId.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  if (words.length === 0) return false;
  if (words.some((w) => CHANGE_WORDS.has(w) || SENSITIVE_WORDS.has(w) || CONNECTOR_WORDS.has(w))) return false;
  // The operation has to be *led* by a read verb: the first verb in the id (ids start with a provider / resource, so look a few
  // words in) must be one that only reads. An id with no recognisable verb is not vouched for.
  const verb = words.slice(0, 4).find((w) => READ_VERBS.has(w));
  if (!verb) return false;
  // What is passed matters as much as what the tool is called: database_query with `DELETE FROM ...` is not a read.
  return !argsContainWrite(args);
}
