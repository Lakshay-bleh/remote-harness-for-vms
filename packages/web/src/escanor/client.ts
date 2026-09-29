// Minimal client for the Escanor API (same endpoints as @escanor/sdk), with single-flight token refresh.

export const ESCANOR_API_URL = (
  (import.meta as any).env?.VITE_ESCANOR_API_URL || 'https://api.escanor.in/api/v1'
).replace(/\/+$/, '');

export const APP_SCHEME = 'io.visey.remoteharness';

const KEYS = {
  access: 'rh_escanor_access',
  refresh: 'rh_escanor_refresh',
  workspace: 'rh_escanor_workspace',
  org: 'rh_escanor_org',
};

export type EscanorUser = { id: string; email: string; name: string | null; avatarUrl: string | null };
export type EscanorSession = { user: EscanorUser; workspaceId: string | null; orgId: string | null };

export type CatalogProvider = {
  id: string;
  name: string;
  description: string;
  authType?: string;
  implementationStatus?: string;
  supportsOauth: boolean;
};
export type CatalogCategory = { id: string; label: string; description: string; providers: CatalogProvider[] };
export type Connection = { providerId: string; isActive: boolean };

export class EscanorApiError extends Error {
  constructor(message: string, public status: number) {
    super(message);
  }
}

export const tokens = {
  access: () => localStorage.getItem(KEYS.access),
  refresh: () => localStorage.getItem(KEYS.refresh),
  set(access: string, refresh: string) {
    localStorage.setItem(KEYS.access, access);
    localStorage.setItem(KEYS.refresh, refresh);
  },
  clear() {
    Object.values(KEYS).forEach((k) => localStorage.removeItem(k));
  },
};

let onAuthFailure: (() => void) | null = null;
export function setAuthFailureHandler(fn: (() => void) | null) {
  onAuthFailure = fn;
}

let refreshing: Promise<void> | null = null;

async function refreshTokens(): Promise<void> {
  refreshing ??= (async () => {
    const refresh = tokens.refresh();
    if (!refresh) throw new EscanorApiError('No refresh token', 401);
    const res = await fetch(`${ESCANOR_API_URL}/auth/refresh`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ refresh_token: refresh }),
    });
    if (!res.ok) {
      if (res.status === 401 || res.status === 403) onAuthFailure?.();
      throw new EscanorApiError('Token refresh failed', res.status);
    }
    const data = await res.json();
    tokens.set(data.access_token, data.refresh_token);
  })().finally(() => {
    refreshing = null;
  });
  return refreshing;
}

async function request<T>(path: string, init?: RequestInit, retry = true): Promise<T> {
  const headers = new Headers(init?.headers);
  headers.set('content-type', 'application/json');
  const access = tokens.access();
  if (access) headers.set('authorization', `Bearer ${access}`);
  const org = localStorage.getItem(KEYS.org);
  const ws = localStorage.getItem(KEYS.workspace);
  if (org) headers.set('x-organization-id', org);
  if (ws) headers.set('x-workspace-id', ws);

  const res = await fetch(`${ESCANOR_API_URL}${path}`, { ...init, headers });
  if (res.status === 401 && retry && tokens.refresh()) {
    await refreshTokens();
    return request<T>(path, init, false);
  }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new EscanorApiError(typeof body.detail === 'string' ? body.detail : `Request failed: ${res.status}`, res.status);
  }
  return res.json() as Promise<T>;
}

export const escanor = {
  async googleAuthorizeUrl(platform: 'mobile' | 'web', redirectUri: string): Promise<string> {
    const q = new URLSearchParams({ platform, redirect_uri: redirectUri });
    const { authorization_url } = await request<{ authorization_url: string }>(`/auth/oauth/google/authorize?${q}`);
    return authorization_url;
  },

  async exchangeLoginCode(code: string, provider?: string): Promise<void> {
    const data = await request<{ access_token: string; refresh_token: string }>('/auth/oauth/exchange', {
      method: 'POST',
      body: JSON.stringify(provider ? { code, provider } : { code }),
    });
    tokens.set(data.access_token, data.refresh_token);
  },

  async getSession(): Promise<EscanorSession> {
    const d = await request<any>('/auth/session');
    if (d.active_workspace_id) localStorage.setItem(KEYS.workspace, d.active_workspace_id);
    if (d.active_organization_id) localStorage.setItem(KEYS.org, d.active_organization_id);
    return {
      user: { id: d.user.id, email: d.user.email, name: d.user.name ?? null, avatarUrl: d.user.avatar_url ?? null },
      workspaceId: d.active_workspace_id ?? null,
      orgId: d.active_organization_id ?? null,
    };
  },

  async getCatalog(): Promise<CatalogCategory[]> {
    const d = await request<any>('/integrations/catalog');
    const cats: any[] = Array.isArray(d?.categories) ? d.categories : [];
    return cats
      .filter((c) => c && typeof c.id === 'string' && Array.isArray(c.providers) && c.id !== 'ai-providers')
      .map((c) => ({
        id: c.id,
        label: c.label ?? c.id,
        description: c.description ?? '',
        providers: c.providers
          .filter((p: any) => p && typeof p.id === 'string' && ['live', 'stub'].includes(p.implementationStatus))
          .map((p: any) => ({
            id: p.id,
            name: p.name ?? p.id,
            description: p.description ?? '',
            authType: p.authType,
            implementationStatus: p.implementationStatus,
            supportsOauth: p.supports_oauth ?? p.authType === 'oauth',
          })),
      }))
      .filter((c) => c.providers.length > 0);
  },

  async listConnections(): Promise<Connection[]> {
    const rows = await request<any[]>('/connections');
    return rows.map((r) => ({ providerId: r.provider_id, isActive: Boolean(r.is_active) }));
  },

  async integrationAuthorizeUrl(providerId: string, platform: 'mobile' | 'web', redirectUri: string) {
    const q = new URLSearchParams({ platform, redirect_uri: redirectUri });
    const d = await request<any>(`/auth/integrations/${encodeURIComponent(providerId)}/authorize?${q}`);
    const url: string = d.authorization_url ?? d.authorize_url ?? '';
    if (!/^https:\/\//.test(url)) throw new Error('The server returned an invalid authorization URL.');
    return url;
  },

  async exchangeIntegration(providerId: string, code: string, state: string | null, redirectUri: string) {
    return request<{ synced?: boolean; success?: boolean; message?: string }>(
      `/auth/integrations/${encodeURIComponent(providerId)}/exchange`,
      { method: 'POST', body: JSON.stringify({ code, state, redirect_uri: redirectUri }) },
    );
  },
};
