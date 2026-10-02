// The agent loads HUB_TOKEN/HUB_URL from .env into process.env. Claude child
// processes run model-chosen shell commands, so anything they inherit can be
// read with `env`. HUB_TOKEN is shared by the whole tenant and lets its holder
// impersonate any VM, so it must never reach them. ANTHROPIC_API_KEY stays: it
// is the child's own credential when the VM isn't logged in via `claude`.
const HUB_ONLY = ['HUB_TOKEN', 'HUB_URL'];

export function childEnv(base: NodeJS.ProcessEnv, overrides: Record<string, string> = {}): Record<string, string | undefined> {
  const env: Record<string, string | undefined> = { ...base, ...overrides };
  for (const key of HUB_ONLY) delete env[key];
  return env;
}
