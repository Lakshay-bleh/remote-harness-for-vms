import { resolve } from 'node:path';
import { isWeakSecret } from '@remote-harness/shared/validate';

function requiredValue(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  if (isWeakSecret(v)) throw new Error(`${name} must be a random secret of at least 24 characters (not a placeholder like "change-me")`);
  return v;
}
const required = requiredValue;

export const config = {
  port: Number(process.env.PORT || 8787),
  hubAgentToken: required('HUB_AGENT_TOKEN'),
  appPassword: required('APP_PASSWORD'),
  // Key for encrypting stored MCP tokens. Set HUB_ENCRYPTION_KEY to keep them readable across a
  // HUB_AGENT_TOKEN rotation; otherwise the agent token is the root secret.
  encryptionKey: process.env.HUB_ENCRYPTION_KEY ? requiredValue('HUB_ENCRYPTION_KEY') : undefined,
  // Set TRUST_PROXY=1 only when the hub sits behind a proxy you control that sets X-Forwarded-For.
  trustProxy: process.env.TRUST_PROXY === '1',
  // Set ESCANOR_MCP_ALLOW_PRIVATE=1 to let the hub hand VMs a loopback/private-network MCP URL (dev only).
  allowPrivateMcp: process.env.ESCANOR_MCP_ALLOW_PRIVATE === '1',
  dataDir: resolve(process.env.DATA_DIR || './data'),
  escanorApiUrl: (process.env.ESCANOR_API_URL || 'https://api.escanor.in/api/v1').replace(/\/+$/, ''),
  allowedEmails: (process.env.HUB_ALLOWED_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean),
  webDist: resolve(process.env.WEB_DIST || '../web/dist'),
};
