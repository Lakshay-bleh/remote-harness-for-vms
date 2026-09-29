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

// ---------- MCP server helpers (pure; used by the Node hub and the Worker hub alike) ----------

const HEADER_NAME_RE = /^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,64}$/;
const MAX_HEADERS = 16;
const MAX_HEADER_VALUE = 4096;

export type ParsedMcpServerInput = { ok: true; server: Omit<ManagedMcpServer, 'updatedAt'> } | { ok: false; error: string };

export function parseMcpServerInput(name: string, body: unknown): ParsedMcpServerInput {
  if (!MCP_SERVER_NAME_RE.test(name)) {
    return { ok: false, error: 'Server name must be 1-32 chars of a-z, 0-9, "_" or "-", starting with a letter or digit' };
  }
  const b = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;

  if (typeof b.url !== 'string') return { ok: false, error: 'url is required' };
  let url: URL;
  try {
    url = new URL(b.url.trim());
  } catch {
    return { ok: false, error: 'url is not a valid URL' };
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return { ok: false, error: 'url must be http(s)' };
  if (url.username || url.password) return { ok: false, error: 'url must not embed credentials; use headers' };

  let headers: Record<string, string> | undefined;
  if (b.headers !== undefined && b.headers !== null) {
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

  return {
    ok: true,
    server: {
      name,
      url: url.toString(),
      headers,
      autoAllow: b.autoAllow === undefined ? true : Boolean(b.autoAllow),
      autoAllowReads: b.autoAllowReads === undefined ? false : Boolean(b.autoAllowReads),
      alwaysLoad: b.alwaysLoad === undefined ? true : Boolean(b.alwaysLoad),
      managedBy: typeof b.managedBy === 'string' ? b.managedBy.slice(0, 32) : undefined,
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
]);

// Reading these is itself sensitive; a person should see the request first.
const SENSITIVE_WORDS = new Set(['secret', 'secrets', 'password', 'passwords', 'credential', 'credentials', 'token', 'tokens', 'key', 'keys', 'apikey', 'apikeys', 'private', 'ssh', 'cert', 'certificate', 'certificates', 'env', 'vault']);

// The tools Escanor's MCP server exposes for discovery. They never change anything.
const ESCANOR_READ_ONLY_TOOLS = new Set(['escanor_list_providers', 'escanor_connection_status', 'escanor_list_tools', 'escanor_usage_stats']);

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
  if (words.some((w) => CHANGE_WORDS.has(w) || SENSITIVE_WORDS.has(w))) return false;
  return words.some((w) => READ_VERBS.has(w));
}
