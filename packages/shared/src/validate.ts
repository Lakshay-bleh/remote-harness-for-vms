// Runtime validation shared by the Node hub and the Cloudflare Worker hub.
// Pure TypeScript with no Node- or Workers-specific imports, so both runtimes
// run exactly the same checks. Everything here treats its input as hostile.
import type {
  AgentToHubMessage,
  EffortLevel,
  ImageAttachment,
  PermissionDecision,
  PermissionMode,
} from './protocol';

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isString = (v: unknown): v is string => typeof v === 'string';
const isOptString = (v: unknown): boolean => v === undefined || isString(v);
const isId = (v: unknown): v is string => isString(v) && v.length > 0 && v.length <= 256;
const isOptId = (v: unknown): boolean => v === undefined || isId(v);

// ---------- agent -> hub frames ----------

// Agent frames come from a network peer holding a (tenant-shared) token, so they
// are untrusted: reject anything that doesn't match the protocol shape instead of
// letting undefined/odd types reach SQLite binds or handlers.
export function parseAgentFrame(raw: string): AgentToHubMessage | null {
  let m: unknown;
  try {
    m = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!isObject(m)) return null;

  const ok = (cond: boolean) => (cond ? (m as AgentToHubMessage) : null);
  switch (m.type) {
    case 'hello':
      return ok(isId(m.vmName) && Array.isArray(m.accounts) && Array.isArray(m.sessions));
    case 'sdk_message':
      return ok(isId(m.sessionId) && isOptId(m.tempId));
    case 'session_created':
      return ok(isId(m.tempId) && isId(m.sessionId) && isString(m.cwd) && isString(m.title) && isString(m.accountId));
    case 'session_ended':
      return ok(isId(m.sessionId) && isOptString(m.reason));
    case 'permission_request':
      return ok(isId(m.sessionId) && isId(m.requestId) && isId(m.toolName) && isObject(m.input) && isOptString(m.blockedPath));
    case 'error':
      return ok(isString(m.message) && isOptId(m.sessionId) && isOptId(m.tempId));
    case 'projects_list':
      return ok(isId(m.requestId) && Array.isArray(m.projects) && m.projects.every(isString));
    default:
      return null;
  }
}

// ---------- browser -> hub request bodies ----------

const MAX_TEXT_CHARS = 200_000;
const MAX_IMAGES = 10;
const MAX_IMAGE_B64_CHARS = 15_000_000;
const IMAGE_TYPE = /^image\/(png|jpe?g|gif|webp)$/;

export type UserInput = { text: string; images: ImageAttachment[] | undefined };

export function parseUserInput(body: unknown): Result<UserInput> {
  if (!isObject(body)) return { ok: false, error: 'JSON object body required' };
  const { text, images } = body;
  if (text !== undefined && !isString(text)) return { ok: false, error: 'text must be a string' };
  if (isString(text) && text.length > MAX_TEXT_CHARS) return { ok: false, error: 'text too long' };

  let parsed: ImageAttachment[] | undefined;
  if (images !== undefined) {
    if (!Array.isArray(images)) return { ok: false, error: 'images must be an array' };
    if (images.length > MAX_IMAGES) return { ok: false, error: `at most ${MAX_IMAGES} images` };
    parsed = [];
    for (const img of images) {
      if (!isObject(img) || !isString(img.mediaType) || !IMAGE_TYPE.test(img.mediaType) || !isString(img.dataBase64) || !img.dataBase64) {
        return { ok: false, error: 'each image needs an image/* mediaType and dataBase64' };
      }
      if (img.dataBase64.length > MAX_IMAGE_B64_CHARS) return { ok: false, error: 'image too large' };
      parsed.push({ mediaType: img.mediaType, dataBase64: img.dataBase64 });
    }
  }
  if (!text && !(parsed && parsed.length > 0)) return { ok: false, error: 'text or images required' };
  return { ok: true, value: { text: text ?? '', images: parsed } };
}

export type NewSessionInput = UserInput & { cwd: string | undefined; accountId: string | undefined };

export function parseNewSession(body: unknown): Result<NewSessionInput> {
  const base = parseUserInput(body);
  if (!base.ok) return base;
  const { cwd, accountId } = body as Record<string, unknown>;
  if (cwd !== undefined && (!isString(cwd) || cwd.length > 1024)) return { ok: false, error: 'cwd must be a string' };
  if (accountId !== undefined && !isId(accountId)) return { ok: false, error: 'accountId must be a string' };
  return { ok: true, value: { ...base.value, cwd: cwd as string | undefined, accountId: accountId as string | undefined } };
}

const PERMISSION_MODES: readonly string[] = ['default', 'acceptEdits', 'bypassPermissions', 'plan', 'dontAsk', 'auto'] satisfies PermissionMode[];
const EFFORT_LEVELS: readonly string[] = ['low', 'medium', 'high', 'xhigh', 'max'] satisfies EffortLevel[];
const BEHAVIORS: readonly string[] = ['allow', 'deny'] satisfies PermissionDecision[];

export const isPermissionMode = (v: unknown): v is PermissionMode => isString(v) && PERMISSION_MODES.includes(v);
export const isEffortLevel = (v: unknown): v is EffortLevel => isString(v) && EFFORT_LEVELS.includes(v);
export const isPermissionBehavior = (v: unknown): v is PermissionDecision => isString(v) && BEHAVIORS.includes(v);
export const isIdString = isId;

// ---------- secrets ----------

// Constant-time-ish string comparison. Non-strings and empty strings never match, so an
// unset secret (undefined/'') can't be satisfied by an attacker-supplied "undefined" or "".
export function safeEqual(a: unknown, b: unknown): boolean {
  if (!isString(a) || !isString(b) || a.length === 0 || b.length === 0) return false;
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

// Refuses unset, short, placeholder (.env.example "change-me") and single-character-repeat secrets.
export function isWeakSecret(v: unknown): boolean {
  if (!isString(v) || v.length < 24) return true;
  if (/change[-_ ]?me|replace|example|your[-_ ]?(secret|token|password)/i.test(v)) return true;
  return new Set(v).size < 6;
}

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
export function validateMcpUrl(url: unknown, opts: { allowPrivate?: boolean } = {}): Result<string> {
  if (!isString(url) || url.length > 2048) return { ok: false, error: 'url required' };
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

// ---------- brute-force limiter ----------

export class RateLimiter {
  private entries = new Map<string, { count: number; resetAt: number }>();
  private maxFailures: number;
  private windowMs: number;
  private maxKeys: number;
  private now: () => number;

  constructor(opts: { maxFailures: number; windowMs: number; maxKeys?: number; now?: () => number }) {
    this.maxFailures = opts.maxFailures;
    this.windowMs = opts.windowMs;
    this.maxKeys = opts.maxKeys ?? 10_000;
    this.now = opts.now ?? Date.now;
  }

  blocked(key: string): boolean {
    const e = this.entries.get(key);
    if (!e) return false;
    if (this.now() >= e.resetAt) {
      this.entries.delete(key);
      return false;
    }
    return e.count >= this.maxFailures;
  }

  fail(key: string): void {
    const t = this.now();
    const e = this.entries.get(key);
    if (e && t < e.resetAt) {
      e.count++;
      return;
    }
    this.entries.delete(key);
    while (this.entries.size >= this.maxKeys) {
      const oldest = this.entries.keys().next().value;
      if (oldest === undefined) break;
      this.entries.delete(oldest);
    }
    this.entries.set(key, { count: 1, resetAt: t + this.windowMs });
  }

  succeed(key: string): void {
    this.entries.delete(key);
  }

  size(): number {
    return this.entries.size;
  }
}

export function clampLimit(raw: unknown, def: number, max: number): number {
  const n = typeof raw === 'string' ? Number.parseInt(raw, 10) : NaN;
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(n, max);
}

// ---------- redaction before persistence ----------

const REDACTED = '[REDACTED]';
const SENSITIVE_KEY = /^(authorization|proxy-authorization|x-api-key|api[-_]?key|password|passwd|secret|token|access[-_]?token|refresh[-_]?token|client[-_]?secret|private[-_]?key)$/i;
const SECRET_PATTERNS: RegExp[] = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
  /\bsk-ant-[A-Za-z0-9_-]{20,}/g,
  /\besc_[a-z]+_[A-Za-z0-9_-]{20,}/g,
  /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g,
  /\bgh[pousr]_[A-Za-z0-9]{30,}\b/g,
  /\bgithub_pat_[A-Za-z0-9_]{20,}/g,
  /\bxox[abprs]-[A-Za-z0-9-]{10,}/g,
  /\beyJ[A-Za-z0-9_-]{5,}\.eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{10,}/g,
  /\bBearer\s+[A-Za-z0-9._~+/=-]{20,}/g,
];
const MAX_REDACT_DEPTH = 64;

function redactString(s: string): string {
  let out = s;
  for (const re of SECRET_PATTERNS) out = out.replace(re, REDACTED);
  return out;
}

// Transcripts and permission inputs are stored verbatim and can echo credentials the model saw (env dumps,
// curl commands, tool output). Mask well-known secret formats and values under sensitive keys. Returns a
// copy; the input is never mutated, and cycles / very deep structures are handled.
export function redactSecrets(value: unknown, depth = 0, seen: WeakSet<object> = new WeakSet()): unknown {
  if (typeof value === 'string') return redactString(value);
  if (value === null || typeof value !== 'object') return value;
  if (seen.has(value)) return '[CIRCULAR]';
  if (depth >= MAX_REDACT_DEPTH) return '[TRUNCATED]';
  seen.add(value);
  if (Array.isArray(value)) return value.map((v) => redactSecrets(v, depth + 1, seen));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    out[k] = SENSITIVE_KEY.test(k) && v !== null && v !== undefined && v !== '' ? REDACTED : redactSecrets(v, depth + 1, seen);
  }
  return out;
}
