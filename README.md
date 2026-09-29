# Remote Harness

Your own remote control for Claude Code, running entirely on infrastructure you own. No
Anthropic Remote Control involved: a small **agent** you install on each VM drives real
Claude Code sessions via the Claude Agent SDK, a **hub** you run once holds chat history
and auth, and a **web app** (installable as a PWA on your phone) gives you one chat-style
window over every session on every VM.

```
packages/
  shared/   wire protocol types shared by all three pieces
  agent/    installed on each VM — runs Claude Code sessions, talks to the hub
  hub/      the server you run once — auth, persistence, realtime relay
  web/      the chat UI (React + Vite), installable as a PWA on desktop or mobile
```

## How it fits together

- Each **agent** dials **out** to the hub over a WebSocket (`/agent`), so there's no
  inbound firewall/NAT setup needed on the VM. It authenticates with a shared
  `HUB_AGENT_TOKEN`.
- The agent drives Claude Code sessions with `@anthropic-ai/claude-agent-sdk` using
  streaming input, so a session stays open across turns, tool permission requests are
  routed back to you as interactive approve/deny prompts, and sessions can be resumed
  after an agent restart.
- The **hub** persists every message to a local SQLite database (via Node's built-in
  `node:sqlite`, so no native build step), serves the REST API, and pushes live updates
  to connected browsers over `/ws`.
- The **web app** is a single-page PWA. Install it to your phone's home screen for a
  native-feeling app; it also works as a normal desktop browser tab.

## 1. Run the hub

```bash
npm install
cp packages/hub/.env.example packages/hub/.env   # edit HUB_AGENT_TOKEN and APP_PASSWORD
npm run build:web                                 # builds packages/web/dist, which the hub serves
npm run dev:hub                                   # or: npm run start -w @remote-harness/hub
```

Put the hub somewhere reachable from wherever you'll use the app (a small VPS, or your
own machine on a tailnet). Open `http://<hub-host>:8787`, sign in with `APP_PASSWORD`,
and — on your phone — use "Add to Home Screen" to install it.

For production, put the hub behind a reverse proxy (Caddy/nginx) that terminates TLS, so
the app can be installed and used as `https://...` (required for PWA installability and
service workers on most platforms).

## 2. Install the agent on each VM

One-liner (clones the repo into `~/remote-harness-for-vms` and runs the installer):

```bash
curl -fsSL https://raw.githubusercontent.com/yashmishra2006/remote-harness-for-vms/main/packages/agent/bootstrap.sh | bash
```

Or copy this repo to the VM yourself (git clone, scp, whatever) and run the installer directly:

```bash
./packages/agent/install.sh
```

The script installs dependencies, asks for the hub URL, the shared `HUB_AGENT_TOKEN`, a
name for the VM, the workspace root Claude is allowed to work in, and (if this machine
hasn't already run `claude` interactively) an `ANTHROPIC_API_KEY`. It then installs and
starts a `systemd` service (`remote-harness-agent`) that keeps the agent running and
reconnects automatically.

The VM shows up in the app automatically the first time its agent connects — no manual
registration step.

### Multiple Claude accounts per VM

`install.sh` also asks how many separate Claude accounts you want on that VM. Say 3 and
it creates `~/.claude-profiles/claude1`, `claude2`, `claude3` (each an isolated
`CLAUDE_CONFIG_DIR`, so its own login) and matching `claude1`/`claude2`/`claude3` aliases
in `~/.bashrc` — log in to each once with `claude1` (then `/login`), etc. The agent
detects these on startup and reports them to the hub; if a VM has more than one account,
the sidebar groups that VM's chats by account, and "+ New chat" appears under each
account. Already manage accounts this way yourself? Symlink your existing config dirs
into `$PROFILES_DIR` instead of re-running setup — see `packages/agent/.env.example`.

## Notes on the design

- **Permissions**: tool calls Claude would normally ask you about (Bash, Edit, Write,
  etc.) are routed to the app as an inline "Permission requested" card with Allow/Deny.
  The chat composer also has pill selectors for permission mode (Default / Auto / Accept
  edits / Bypass permissions / Plan / Don't ask), model (Sonnet 5.5 / Opus 5.5 / Haiku 4.5 /
  Fable 5.1 / provider default), and reasoning effort (Low / Medium / High / xHigh / Max),
  matching Claude Code's own UI — changes apply live, mid-session.
- **Multiple sessions per VM**: each chat in the sidebar is an independent Claude Code
  session (its own working directory and history), listed under its VM (and under its
  Claude account, when a VM has more than one).
- **Images**: attach or paste images into the composer; they're sent as base64 content
  blocks alongside your message, same as Claude Code's own image support.
- **Auth**: single shared `APP_PASSWORD` for the app and a single shared
  `HUB_AGENT_TOKEN` for all agents — deliberately simple for personal/small-team use.
  Put the hub behind TLS if it's reachable from the internet.

## MCP servers on every VM (Escanor)

The hub can install an MCP server into **every Claude session on every VM** — chats that are
already running included — so tools are there the moment you start typing, with nothing to
configure per machine. [Escanor](https://www.escanor.in) uses this to add its integration tools
(GitHub, Vercel, AWS, …) to all your sessions.

**As a user:** open **Connect to Escanor** at the bottom of the sidebar, copy the hub URL and
session token, and paste them in Escanor under *Integrations → Claude cloud sessions*. You can
edit or disconnect there at any time; nothing needs restarting. The hub URL must be reachable
from the internet (a reverse proxy, a tunnel, or the Cloudflare Worker hub) — Escanor's servers
dial it.

**How it works:** the hub stores the set of servers and pushes the *complete* set to each agent
(`set_mcp_servers`) when the agent connects and whenever the set changes. So a new VM, or one
that was offline, converges by itself. The agent passes the set to every new session's
`mcpServers`, applies it to running sessions with the SDK's `setMcpServers` (no restart), and
reports each server's real connection state back to the hub.

**Approval.** With `autoAllow` (the default) the agent approves the server's tools itself, per
call, so chats never stall on a permission card. It is decided per call from the *current* set,
not baked into the session, so turning `autoAllow` off takes effect on the very next call in
chats that are already running — the tool then shows the normal Allow/Deny card. (In *Don't
ask* mode, which denies anything not pre-approved by your own settings, the tools are denied.)

**API** (same bearer token as the rest of `/api`; CORS-enabled like the rest):

```
GET    /api/mcp-servers          servers (header *names* only) + per-VM state
PUT    /api/mcp-servers/:name    { url, headers?, autoAllow?, alwaysLoad?, managedBy? }
DELETE /api/mcp-servers/:name
```

`name` is the server's namespace in Claude Code (`mcp__<name>__<tool>`), so it is limited to
`[a-z0-9_-]`, 32 chars. Header values are credentials: accepted, stored, pushed to agents, and
never returned by the API. `autoAllow` and `alwaysLoad` default to `true`; the latter loads the
server's tools into every prompt instead of deferring them behind tool search.

## Local development

```bash
npm run dev:hub    # hub on :8787
npm run dev:web    # vite dev server on :5173, proxies /api and /ws to the hub
npm run dev:agent  # agent, pointed at HUB_URL in packages/agent/.env
```

## Android app

The web UI also ships as a native Android app (Capacitor). It has a **Hub URL** field on the
login screen — enter the address where your hub runs, then the password.

```bash
# needs JDK 21 + Android SDK (JAVA_HOME / ANDROID_HOME set)
npm run build:apk    # -> packages/web/android/app/build/outputs/apk/debug/app-debug.apk
```

## Deploy the hub to Cloudflare Workers (optional)

`packages/worker` is the same hub running on Cloudflare (one Durable Object with SQLite
storage holds the database and both WebSocket groups), so you get a permanent public
`https://` address with nothing to keep running yourself. It also serves the web UI.

```bash
cd packages/worker
npx wrangler login
npx wrangler secret put HUB_AGENT_TOKEN   # same value your agents use
npx wrangler secret put APP_PASSWORD      # web / Android login password
cd ../.. && npm run deploy:worker
```

Then point each agent at it with `HUB_URL=wss://<your-worker>.workers.dev/agent` and use
`https://<your-worker>.workers.dev` as the Hub URL in the Android app.
