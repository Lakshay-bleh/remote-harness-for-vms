import type { AssistantCapabilities, AssistantConversation, AssistantMessages, AssistantStatus, AssistantUsage, MachineView } from '@remote-harness/shared/escanor';
import { isNative } from '../api';
import { escanorApiBase } from './config';
import type { BillingPlan, BillingSub } from './account/billing';
import type { ApiAttachment } from './composer/attachments';
import type { ConsentState } from './account/privacy';
import type { ManagedHub } from './managed';
import type { ServerPlan } from './voice/serverPlan';

const ACCESS = 'escanor_access';
const REFRESH = 'escanor_refresh';
const EXPIRES = 'escanor_access_expires';
/** Renew the access token this long before it runs out, so a request is never sent with one about to be refused. */
const RENEW_EARLY_MS = 90_000;
/** What the server gives an access token when it does not say (it lives 15 minutes). */
const DEFAULT_ACCESS_SECONDS = 900;

export class SessionEnded extends Error {
  constructor() {
    super('Your Escanor session ended. Please sign in again.');
  }
}

export class ApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

export interface EscanorUser {
  id: string;
  email: string;
  name: string;
  avatar_url?: string | null;
}

export interface CatalogProvider {
  id: string;
  name: string;
  description: string;
  category_label: string;
  connected: boolean;
  connect_via: 'oauth' | 'api_key' | 'credentials' | 'local_agent' | string;
  can_connect: boolean;
  oauth_available: boolean;
  credential_fields: string[];
  token_label: string;
  help_url: string;
}

export interface McpConnection {
  id: string;
  name: string;
  token_prefix: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
  total_calls: number;
  managed_by?: string | null;
}

/** What the person chose to be told about; the same switches as on the website. */
export interface NotificationPrefs {
  push_enabled: boolean;
  emergency_alerts: boolean;
  server_down: boolean;
  deployment_approvals: boolean;
  team_pings: boolean;
}

export interface Subscription {
  plan_name?: string;
  plan_id?: string;
  status?: string;
  [k: string]: unknown;
}

export interface McpInstall {
  endpoint: string;
  token: string;
  cli_command: string;
  token_id?: string;
}

export interface WorkspaceSettings {
  organization_name: string;
  workspace_name: string;
  default_region: string;
  environment: string;
  session_timeout: string;
  two_factor_enabled: boolean;
  connected_devices: number;
}

export interface OrgMember {
  user_id: string;
  email: string;
  name: string;
  role: string;
  joined_at: string | null;
}

export interface AuditLine {
  id?: string;
  created_at: string;
  actor_email: string | null;
  action: string;
  target: string;
  status: string;
  detail: string;
}

export interface PrivacyRequest {
  id: string;
  reference: string;
  request_type: string;
  status: string;
  subject: string;
  received_at: string;
  acknowledge_by: string;
  resolve_by: string;
  acknowledged_at: string | null;
  resolved_at: string | null;
  resolution_note: string | null;
  events?: Array<{ from_status: string | null; to_status: string; note: string | null; created_at: string }>;
}

export interface TwoFactorStatus {
  enabled: boolean;
  enrolled_at: string | null;
  backup_codes_left: number;
}

export interface DeletionStatus {
  scheduled: boolean;
  requested_at: string | null;
  scheduled_for: string | null;
  grace_days: number;
  two_factor_enabled: boolean;
  reference?: string;
}

const tokens = {
  get access() {
    return localStorage.getItem(ACCESS);
  },
  get refresh() {
    return localStorage.getItem(REFRESH);
  },
  /** When the access token stops working (ms since 1970), or 0 when unknown. */
  get expiresAt() {
    return Number(localStorage.getItem(EXPIRES)) || 0;
  },
  set(access: string, refresh: string, expiresInSeconds = DEFAULT_ACCESS_SECONDS) {
    localStorage.setItem(ACCESS, access);
    localStorage.setItem(REFRESH, refresh);
    localStorage.setItem(EXPIRES, String(Date.now() + expiresInSeconds * 1000));
  },
  clear() {
    localStorage.removeItem(ACCESS);
    localStorage.removeItem(REFRESH);
    localStorage.removeItem(EXPIRES);
  },
};

/** Is it time to get a new access token before asking for anything? True when its end is near, or already past. */
export function accessIsStale(expiresAt: number, now = Date.now()): boolean {
  return expiresAt > 0 && now >= expiresAt - RENEW_EARLY_MS;
}

/** Online now, or heard from within `windowMs` (default ten minutes). */
export function isRecentlySeen(status: string, lastHeartbeat?: string | null, now = Date.now(), windowMs = 600_000): boolean {
  if (status === 'online') return true;
  const t = lastHeartbeat ? Date.parse(lastHeartbeat) : NaN;
  return Number.isFinite(t) && now - t >= 0 && now - t < windowMs;
}

export const hasStoredSession = (): boolean => Boolean(tokens.refresh || tokens.access);

/** The backend's error text, whatever shape it came in. */
export function messageOf(body: unknown, fallback: string): string {
  const detail = (body as { detail?: unknown } | null)?.detail;
  if (typeof detail === 'string' && detail) return detail;
  if (Array.isArray(detail) && detail[0]?.msg) return String(detail[0].msg);
  return fallback;
}

/** `ok`: new tokens saved. `rejected`: the server says this session is over. `unavailable`: could not tell (offline, a server error). */
export type RefreshResult = 'ok' | 'rejected' | 'unavailable';

/** Only a refusal of the refresh token itself ends a session; a busy or unreachable server must never sign anyone out. */
export function refreshOutcome(status: number): RefreshResult {
  return status === 400 || status === 401 || status === 403 ? 'rejected' : 'unavailable';
}

let refreshing: Promise<RefreshResult> | null = null;

/** One refresh at a time, however many requests found the token expired together. */
async function refreshTokens(): Promise<RefreshResult> {
  refreshing ??= (async (): Promise<RefreshResult> => {
    const refresh = tokens.refresh;
    if (!refresh) return 'rejected';
    try {
      const res = await fetch(`${escanorApiBase()}/auth/refresh`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refresh_token: refresh }) });
      if (!res.ok) return refreshOutcome(res.status);
      const body = await res.json();
      tokens.set(body.access_token, body.refresh_token ?? refresh, Number(body.expires_in) || DEFAULT_ACCESS_SECONDS);
      return 'ok';
    } catch {
      return 'unavailable'; // offline is not "signed out": keep the tokens and let the caller see the network error
    }
  })().finally(() => {
    refreshing = null;
  });
  return refreshing;
}

/**
 * Send a request signed in. A person is signed out only when the server refuses the refresh token itself: a refused access token is
 * the ordinary 15-minute expiry (or another request renewing it at the same moment), never a reason to sign anyone out.
 */
async function request<T>(path: string, init: RequestInit = {}, opts: { auth?: boolean } = {}): Promise<T> {
  const auth = opts.auth !== false;
  let used: string | null = null;
  const send = () => {
    used = auth ? tokens.access : null;
    return fetch(`${escanorApiBase()}${path}`, {
      ...init,
      headers: { 'content-type': 'application/json', ...(used ? { authorization: `Bearer ${used}` } : {}), ...init.headers },
    });
  };

  if (auth && accessIsStale(tokens.expiresAt)) {
    // Renew before asking. If the server cannot be reached the old token is still tried: it may have a little time left.
    if ((await refreshTokens()) === 'rejected') {
      tokens.clear();
      throw new SessionEnded();
    }
  }

  let res: Response;
  try {
    res = await send();
  } catch {
    throw new ApiError('Could not reach Escanor. Check your connection.', 0);
  }
  // Up to two renewals: a second request can renew the token between this one leaving and arriving, which makes the first one's
  // fresh token the old one. Trying again with whatever is current settles it.
  for (let attempt = 0; res.status === 401 && auth && attempt < 2; attempt++) {
    if (tokens.access && tokens.access !== used) {
      res = await send(); // another request already renewed it: just use the new one
      continue;
    }
    const refreshed = await refreshTokens();
    if (refreshed === 'unavailable') throw new ApiError('Could not reach Escanor to keep you signed in. Try again in a moment.', 0);
    if (refreshed === 'rejected') {
      tokens.clear();
      throw new SessionEnded();
    }
    res = await send();
  }
  if (res.status === 401 && auth) throw new ApiError('Escanor could not confirm it is you for that. Try again in a moment.', 401);
  if (!res.ok) throw new ApiError(messageOf(await res.json().catch(() => null), `Something went wrong (${res.status}).`), res.status);
  if (res.status === 204) return undefined as T;
  return res.json();
}

const json = (body: unknown): RequestInit => ({ method: 'POST', body: JSON.stringify(body) });
const enc = encodeURIComponent;

export const escanor = {
  // -- session
  // `codeChallenge` (PKCE, S256) binds the login code to this app instance: on Android the code comes back through a custom-scheme
  // link that any installed app can also register, and without the verifier an app that intercepts the code cannot redeem it.
  async authorizeUrl(redirectUri: string, platform: 'web' | 'mobile', codeChallenge?: string): Promise<string> {
    const pkce = codeChallenge ? `&code_challenge=${enc(codeChallenge)}&code_challenge_method=S256` : '';
    const r = await request<{ authorization_url: string }>(`/auth/oauth/google/authorize?platform=${platform}&redirect_uri=${enc(redirectUri)}${pkce}`, {}, { auth: false });
    return r.authorization_url;
  },
  async exchangeCode(code: string, codeVerifier?: string): Promise<void> {
    const t = await request<{ access_token: string; refresh_token: string; expires_in?: number }>('/auth/oauth/exchange', json({ code, provider: 'google', client: isNative() ? 'mobile' : 'web', ...(codeVerifier ? { code_verifier: codeVerifier } : {}) }), { auth: false });
    tokens.set(t.access_token, t.refresh_token, t.expires_in);
  },
  /** For development only: the backend refuses this unless ENABLE_DEV_AUTH is set. */
  async devLogin(email: string): Promise<void> {
    const t = await request<{ access_token: string; refresh_token: string; expires_in?: number }>('/auth/dev/login', json({ email, name: email.split('@')[0] }), { auth: false });
    tokens.set(t.access_token, t.refresh_token, t.expires_in);
  },
  async me(): Promise<EscanorUser> {
    const s = await request<{ user: EscanorUser }>('/auth/session');
    return s.user;
  },
  async signOut(): Promise<void> {
    const refresh = tokens.refresh;
    tokens.clear();
    if (refresh) await request('/auth/logout', json({ refresh_token: refresh }), { auth: false }).catch(() => undefined);
  },

  // -- the hosted hub: the address and this person's tokens for their VMs
  managedHub: () => request<ManagedHub>('/agent/hub/managed'),

  // -- the assistant
  status: () => request<AssistantStatus>('/ai/status'),
  usage: () => request<AssistantUsage>('/ai/usage'),
  capabilities: (live = false) => request<AssistantCapabilities>(`/ai/capabilities${live ? '?live=true' : ''}`),
  machine: (logs = false) => request<MachineView>(`/ai/machine?logs=${logs}&tail=120`),
  conversations: () => request<{ conversations: AssistantConversation[] }>('/ai/conversations').then((r) => r.conversations),
  send: (text: string, conversationId?: string, attachments: ApiAttachment[] = []) => request<{ conversation_id: string }>('/ai/chat', json({ text, conversation_id: conversationId ?? null, ...(attachments.length ? { attachments } : {}) })),
  messages: (id: string, after: number) => request<AssistantMessages>(`/ai/conversations/${enc(id)}/messages?after=${after}`),
  answer: (id: string, requestId: string, allow: boolean) => request<{ status: string }>(`/ai/conversations/${enc(id)}/permissions/${enc(requestId)}`, json({ allow })),
  stop: (id: string) => request<{ ok: boolean }>(`/ai/conversations/${enc(id)}/stop`, { method: 'POST' }),
  remove: (id: string) => request<{ ok: boolean }>(`/ai/conversations/${enc(id)}`, { method: 'DELETE' }),

  // -- integrations (the same backend the web app uses, so the same truth)
  catalog: () => request<{ providers: CatalogProvider[] }>('/integrations/catalog').then((r) => r.providers),
  connectWithKey: (providerId: string, body: { access_token?: string; credentials?: Record<string, string> }) => request<{ synced?: boolean; message?: string }>(`/auth/integrations/${enc(providerId)}/connect`, json(body)),
  integrationAuthorizeUrl: (providerId: string) => request<{ authorization_url: string }>(`/auth/integrations/${enc(providerId)}/authorize?platform=mobile`).then((r) => r.authorization_url),
  disconnect: (providerId: string) => request<{ disconnected: boolean }>(`/auth/integrations/${enc(providerId)}`, { method: 'DELETE' }),

  // -- Escanor Desktop: end-to-end encrypted commands for one of the person's own computers, answered when it next polls.
  /** Queue a command for a computer through the backend and wait for it to finish. The backend only carries what the phone sealed. */
  async runOnComputer(agentId: string, action: string, parameters: Record<string, unknown>, timeoutMs = 120_000): Promise<Record<string, any>> {
    type Cmd = { id: string; status: string; result?: Record<string, any>; error?: string | null };
    let cmd = await request<Cmd>('/agents/commands', json({ agent_id: agentId, plugin: 'desktop', action, parameters, approve_immediately: true, wait_for_result: true }));
    const until = Date.now() + timeoutMs;
    // Quick at first (the computer answers within a second or two when it is awake), then easier on the server.
    for (let n = 0; cmd.status !== 'succeeded' && cmd.status !== 'failed' && cmd.status !== 'cancelled' && Date.now() < until; n++) {
      await new Promise((r) => setTimeout(r, Math.min(1000, 350 + n * 150)));
      cmd = await request<Cmd>(`/agents/commands/${enc(cmd.id)}`);
    }
    if (cmd.status !== 'succeeded') throw new Error(cmd.status === 'failed' ? (cmd.error ?? 'The computer refused that.') : 'The computer did not answer. Is it on and online?');
    return cmd.result ?? {};
  },
  async sendToComputer(agentId: string, deviceId: string, sealed: string): Promise<string> {
    const r = await escanor.runOnComputer(agentId, 'sealed', { dev: deviceId, sealed });
    if (!r.sealed) throw new Error('The computer did not answer. Is it on and online?');
    return String(r.sealed);
  },
  /** The computers of this account that run Escanor Desktop (a phone signed in to the same account can find them to pair). */
  async desktops(): Promise<Array<{ id: string; name: string; online: boolean }>> {
    const r = await request<{ agents: Array<{ id: string; name: string; runtime_status: string; last_heartbeat_at?: string | null; health?: { app?: string } }> }>('/agents');
    // The server calls a computer online for 90 s after its last heartbeat, which is sent every 30 s: one late heartbeat (a busy or
    // briefly sleeping laptop) made a running computer look off. A heartbeat in the last ten minutes is good enough to try it.
    return r.agents.filter((a) => a.health?.app === 'escanor-desktop').map((a) => ({ id: a.id, name: a.name, online: isRecentlySeen(a.runtime_status, a.last_heartbeat_at) }));
  },
  async pairWithDesktop(agentId: string, body: { sel: string; nonce: string; proof: string; name: string }): Promise<{ deviceId: string; sealedKey: string }> {
    const r = await escanor.runOnComputer(agentId, 'pair', body, 45_000); // a computer that is really there answers within seconds
    if (typeof r.deviceId !== 'string' || typeof r.sealedKey !== 'string') throw new Error('The computer did not complete the pairing.');
    return { deviceId: r.deviceId, sealedKey: r.sealedKey };
  },

  // -- the person and their account (the same endpoints the website uses)
  async updateProfile(name: string): Promise<{ name: string }> {
    return request('/users/me', { method: 'PATCH', body: JSON.stringify({ name }) });
  },
  notificationPrefs: () => request<NotificationPrefs>('/users/me/notification-preferences'),
  setNotificationPrefs: (patch: Partial<NotificationPrefs>) => request<NotificationPrefs>('/users/me/notification-preferences', { method: 'PATCH', body: JSON.stringify(patch) }),
  subscription: () => request<Subscription>('/subscription'),
  // -- push notifications: this phone's address, whether the server can send, a test, and forgetting the phone on sign-out
  registerPushToken: (token: string) => request<{ status: string }>('/users/me/push-token', json({ token, platform: 'android' })),
  unregisterPushToken: (token: string) => request<{ removed: number }>('/users/me/push-token', { method: 'DELETE', body: JSON.stringify({ token }) }),
  pushStatus: () => request<{ configured: boolean; devices: number }>('/users/me/push-status'),
  sendTestPush: () => request<{ delivered: number }>('/users/me/push-test', { method: 'POST' }),
  exportMyData: () => request<{ scope?: string; [k: string]: unknown }>('/compliance/me/export'),

  // -- plan and billing
  billingPlans: () => request<{ plans: BillingPlan[] }>('/billing/plans', {}, { auth: false }).then((r) => r.plans),
  billingSubscription: () => request<BillingSub>('/billing/subscription'),
  billingCheckout: (planId: string) => request<{ status?: string; message?: string | null; razorpay_key_id?: string; razorpay_subscription_id?: string; plan_id?: string }>('/billing/checkout', json({ plan_id: planId })),
  billingVerify: (body: { razorpay_payment_id: string; razorpay_subscription_id: string; razorpay_signature: string }) => request<{ status: string; plan_id: string; plan_name: string }>('/billing/verify', json(body)),
  billingCancel: () => request<{ status: string; cancel_at_period_end: boolean }>('/billing/cancel', { method: 'POST' }),

  // -- privacy: what you agreed to, your requests, and a copy of your data
  consents: () => request<ConsentState[]>('/compliance/consents'),
  recordConsent: (purpose: string, grant: boolean, noticeVersion: string) => request<ConsentState>('/compliance/consents', json({ purpose, action: grant ? 'grant' : 'withdraw', notice_version: noticeVersion })),
  privacyRequests: () => request<PrivacyRequest[]>('/compliance/requests'),
  privacyRequest: (id: string) => request<PrivacyRequest>(`/compliance/requests/${enc(id)}`),
  openPrivacyRequest: (body: { request_type: string; subject: string; details: string }) => request<PrivacyRequest>('/compliance/requests', json(body)),

  // -- workspace and team
  workspaceSettings: () => request<WorkspaceSettings>('/workspace/settings'),
  updateWorkspaceSettings: (patch: { workspace_name?: string; default_region?: string; environment?: string }) => request<WorkspaceSettings>('/workspace/settings', { method: 'PATCH', body: JSON.stringify(patch) }),
  organization: () => request<{ your_role: string; members: OrgMember[]; available_roles: string[]; member_count: number }>('/admin/organization'),
  setMemberRole: (userId: string, role: string) => request<{ role: string }>(`/admin/organization/members/${enc(userId)}`, { method: 'PATCH', body: JSON.stringify({ role }) }),
  auditLogs: (limit = 100) => request<{ logs: AuditLine[] }>(`/audit-logs?limit=${limit}`).then((r) => r.logs),

  // -- two-step verification and deleting the account
  twoFactor: () => request<TwoFactorStatus>('/security/2fa'),
  twoFactorSetup: () => request<{ secret: string; otpauth_uri: string; issuer: string; account: string | null }>('/security/2fa/setup', { method: 'POST' }),
  twoFactorEnable: (code: string) => request<{ enabled: boolean; backup_codes: string[] }>('/security/2fa/enable', json({ code })),
  twoFactorDisable: (code: string) => request<{ enabled: boolean }>('/security/2fa/disable', json({ code })),
  twoFactorBackupCodes: (code: string) => request<{ backup_codes: string[] }>('/security/2fa/backup-codes', json({ code })),
  deletionStatus: () => request<DeletionStatus>('/account/deletion'),
  requestDeletion: (code: string, confirmEmail: string) => request<DeletionStatus>('/account/deletion', json({ code, confirm_email: confirmEmail })),
  cancelDeletion: () => request<DeletionStatus>('/account/deletion/cancel', { method: 'POST' }),
  /** How long the backend takes to answer, in ms: the Developer screen's "is it me or the server" check. Needs no sign-in. */
  async ping(): Promise<{ ms: number; ok: boolean; status: number }> {
    const t = performance.now();
    try {
      const res = await fetch(`${escanorApiBase().replace(/\/api\/v1$/, '')}/health`, { cache: 'no-store' });
      return { ms: Math.round(performance.now() - t), ok: res.ok, status: res.status };
    } catch {
      return { ms: Math.round(performance.now() - t), ok: false, status: 0 };
    }
  },

  // -- other AI apps
  mcpConnections: () => request<McpConnection[]>('/agent/mcp/connections'),
  createMcpInstall: (name: string) => request<McpInstall>('/agent/mcp/install', json({ name })),
  renameMcp: (id: string, name: string) => request<{ id: string; name: string }>(`/agent/mcp/connections/${enc(id)}`, { method: 'PATCH', body: JSON.stringify({ name }) }),
  /** A new key in place of this one: the old stops working at once. */
  rotateMcp: (id: string) => request<McpInstall>(`/agent/mcp/connections/${enc(id)}/rotate`, { method: 'POST' }),
  revokeMcp: (id: string) => request<{ success: boolean }>(`/tokens/${enc(id)}`, { method: 'DELETE' }),

  // -- voice: the server's brain for what the phone's own rules do not understand (semantic match, then the AI model)
  voiceResolve: (body: { text: string; client: 'mobile'; device: { platform: string; apps: Array<{ id: string; label: string }> } }) => request<ServerPlan>('/ai/voice/resolve', { ...json(body), signal: AbortSignal.timeout(40_000) }),

  // -- the website, already signed in: a one-minute link, so billing and settings open without a second sign-in
  webHandoff: (next: string) => request<{ url: string; expires_in: number }>('/auth/handoff', json({ next })).then((r) => r.url),
};
