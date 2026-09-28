import { resolve } from 'node:path';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

export const config = {
  port: Number(process.env.PORT || 8787),
  hubAgentToken: required('HUB_AGENT_TOKEN'),
  appPassword: required('APP_PASSWORD'),
  dataDir: resolve(process.env.DATA_DIR || './data'),
  webDist: resolve(process.env.WEB_DIST || '../web/dist'),
};
