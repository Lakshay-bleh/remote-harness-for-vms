import { resolve } from 'node:path';
import { isWeakSecret } from '@remote-harness/shared/validate';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return strong(name, v);
}

function strong(name: string, v: string): string {
  if (isWeakSecret(v)) throw new Error(`${name} must be a random secret of at least 24 characters (not a placeholder like "change-me")`);
  return v;
}

const int = (name: string, fallback: number): number => {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n > 0 ? n : fallback;
};

export const config = {
  port: Number(process.env.PORT || 8787),
  hubAgentToken: required('HUB_AGENT_TOKEN'),
  appPassword: required('APP_PASSWORD'),
  // Optional. Set it to let an operator create isolated tenants on this hub (see admin.ts). It can create and delete
  // tenants and mint credentials, so a weak one is refused just like the others.
  hubAdminToken: process.env.HUB_ADMIN_TOKEN ? strong('HUB_ADMIN_TOKEN', process.env.HUB_ADMIN_TOKEN) : '',
  // The shortest life a machine credential may be given. 60 s in real use; tests lower it to watch one expire.
  machineMinTtlSeconds: Number(process.env.HUB_MACHINE_MIN_TTL_SECONDS || 60),
  // Key for the MCP credentials stored in the database. Defaults to the agent token; set HUB_ENCRYPTION_KEY to keep them
  // readable across a HUB_AGENT_TOKEN rotation.
  encryptionKey: process.env.HUB_ENCRYPTION_KEY ? strong('HUB_ENCRYPTION_KEY', process.env.HUB_ENCRYPTION_KEY) : undefined,
  // Honour X-Forwarded-For when keying the login limiter. Only behind a proxy you control that sets it.
  trustProxy: process.env.TRUST_PROXY === '1',
  // Accept loopback / private-network MCP URLs (a hub that runs beside its MCP server). Metadata addresses never pass.
  allowPrivateMcp: process.env.HUB_MCP_ALLOW_PRIVATE === '1',
  // Old clients put the browser token in the /ws query string, which lands in proxy and CDN logs. Off unless re-enabled.
  allowQueryToken: process.env.HUB_ALLOW_QUERY_TOKEN === '1',
  loginMaxFailures: int('HUB_LOGIN_MAX_FAILURES', 10),
  agentPingMs: int('HUB_AGENT_PING_MS', 30_000),
  agentMaxPayloadBytes: int('HUB_AGENT_MAX_PAYLOAD_BYTES', 32 * 1024 * 1024),
  dataDir: resolve(process.env.DATA_DIR || './data'),
  webDist: resolve(process.env.WEB_DIST || '../web/dist'),
};
