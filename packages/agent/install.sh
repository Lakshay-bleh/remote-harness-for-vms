#!/usr/bin/env bash
# Installs and starts the Remote Harness agent on this VM as a systemd service.
# Run from a copy of this repo on the target machine:
#   ./packages/agent/install.sh
# Or, to clone the repo and run this in one step, see bootstrap.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DIR="$SCRIPT_DIR"
ENV_FILE="$AGENT_DIR/.env"
SERVICE_NAME="remote-harness-agent"
# shellcheck source=envfile.sh
source "$SCRIPT_DIR/envfile.sh"

# When this script is run as `curl ... | bash`, stdin is the script itself,
# not the terminal, so `read` would hit EOF instantly. Read prompts from the
# controlling terminal directly instead.
TTY=/dev/tty
if [ ! -r "$TTY" ] || [ ! -w "$TTY" ]; then
  echo "This installer needs an interactive terminal for setup prompts. Run it directly (not from a non-interactive script) and try again." >&2
  exit 1
fi

echo "==> Checking Node.js"
if ! command -v node >/dev/null 2>&1 || [ "$(node -e 'console.log(process.versions.node.split(".")[0])')" -lt 20 ]; then
  echo "Node.js 20+ is required. Install it (e.g. via nvm or NodeSource) and re-run this script."
  exit 1
fi
echo "    $(node -v) OK"

echo "==> Installing dependencies"
# npm ci installs exactly what package-lock.json pins; npm install can drift to newer, unreviewed versions.
(cd "$REPO_ROOT" && npm ci --no-fund --no-audit --workspace=@remote-harness/agent --workspace=@remote-harness/shared)

if [ ! -f "$ENV_FILE" ]; then
  echo "==> Configuring agent (edit $ENV_FILE later to change these)"
  # HUB_URL / HUB_TOKEN in the environment skip these two questions (the Escanor app hands out a command that sets them).
  if [ -z "${HUB_URL:-}" ]; then
    read -rp "Hub WebSocket URL (e.g. wss://your-hub.example.com/agent): " HUB_URL < "$TTY"
  fi
  if [ -z "${HUB_TOKEN:-}" ]; then
    read -rp "Hub agent token (HUB_AGENT_TOKEN from the hub): " HUB_TOKEN < "$TTY"
  fi
  read -rp "Name for this VM [$(hostname)]: " VM_NAME < "$TTY"
  VM_NAME="${VM_NAME:-$(hostname)}"
  # Not $HOME itself: that would put ~/.ssh, ~/.bashrc and this agent's own .env inside the workspace.
  read -rp "Workspace root directory Claude may work in [$HOME/projects]: " WORKSPACE_ROOT < "$TTY"
  WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects}"
  valid_path "$WORKSPACE_ROOT" && mkdir -p "$WORKSPACE_ROOT"
  read -rp "Folder to scan for projects, shown as pick-a-project options for new chats [$WORKSPACE_ROOT]: " PROJECTS_ROOT < "$TTY"
  PROJECTS_ROOT="${PROJECTS_ROOT:-$WORKSPACE_ROOT}"
  read -rp "ANTHROPIC_API_KEY (leave blank if this machine already ran 'claude' and logged in): " ANTHROPIC_API_KEY < "$TTY"
  # The mode chats start in when the app picks none. The Escanor app's command sets it from your plan: bypassPermissions (this
  # machine runs Claude Code without asking for approval) on Pro and above, default (it asks) otherwise.
  DEFAULT_PERMISSION_MODE="${DEFAULT_PERMISSION_MODE:-default}"

  # Everything below ends up in a file read by the service, so refuse anything that is not what it claims to be.
  need "hub URL (expected wss://host[:port]/path)" valid_hub_url "$HUB_URL"
  need "hub token" valid_hub_token "$HUB_TOKEN"
  need "VM name" valid_vm_name "$VM_NAME"
  need "workspace root" valid_path "$WORKSPACE_ROOT"
  need "projects folder" valid_path "$PROJECTS_ROOT"
  need "ANTHROPIC_API_KEY" valid_api_key "$ANTHROPIC_API_KEY"
  need "DEFAULT_PERMISSION_MODE" valid_permission_mode "$DEFAULT_PERMISSION_MODE"

  # HUB_TOKEN and ANTHROPIC_API_KEY live here: create it owner-only from the start.
  (umask 077; cat > "$ENV_FILE" <<EOF
HUB_URL=$HUB_URL
HUB_TOKEN=$HUB_TOKEN
VM_NAME=$VM_NAME
WORKSPACE_ROOT=$WORKSPACE_ROOT
PROJECTS_ROOT=$PROJECTS_ROOT
DATA_DIR=$AGENT_DIR/data
PROFILES_DIR=$HOME/.claude-profiles
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
DEFAULT_PERMISSION_MODE=$DEFAULT_PERMISSION_MODE
EOF
  )
  echo "    wrote $ENV_FILE"
else
  echo "==> Found existing $ENV_FILE, leaving it as-is"
  # DEFAULT_PERMISSION_MODE included: it is set once, when the machine is first connected, and changed by its owner after that.
  # ...except the hub details when they were passed in, e.g. after the token was rotated.
  if [ -n "${HUB_URL:-}" ] && [ -n "${HUB_TOKEN:-}" ]; then
    need "hub URL (expected wss://host[:port]/path)" valid_hub_url "$HUB_URL"
    need "hub token" valid_hub_token "$HUB_TOKEN"
    set_env_var "$ENV_FILE" HUB_URL "$HUB_URL"
    set_env_var "$ENV_FILE" HUB_TOKEN "$HUB_TOKEN"
    echo "    updated HUB_URL and HUB_TOKEN"
  fi
fi
chmod 600 "$ENV_FILE"

PROFILES_DIR="$HOME/.claude-profiles"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> remote-harness claude profiles >>>"
MARKER_END="# <<< remote-harness claude profiles <<<"

if [ -d "$PROFILES_DIR" ] && [ -n "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]; then
  echo "==> Found existing Claude accounts in $PROFILES_DIR, leaving them as-is:"
  ls "$PROFILES_DIR" | sed 's/^/    /'
else
  echo "==> Set up Claude accounts"
  read -rp "How many separate Claude accounts do you want on this VM? [1]: " ACCOUNT_COUNT < "$TTY"
  ACCOUNT_COUNT="${ACCOUNT_COUNT:-1}"

  if [ "$ACCOUNT_COUNT" -gt 1 ] 2>/dev/null; then
    ALIAS_BLOCK="$MARKER_START"
    for i in $(seq 1 "$ACCOUNT_COUNT"); do
      mkdir -p "$PROFILES_DIR/claude$i"
      ALIAS_BLOCK="$ALIAS_BLOCK
alias claude$i='CLAUDE_CONFIG_DIR=\"$PROFILES_DIR/claude$i\" claude'"
    done
    ALIAS_BLOCK="$ALIAS_BLOCK
$MARKER_END"

    if [ -f "$BASHRC" ] && grep -qF "$MARKER_START" "$BASHRC"; then
      echo "    $BASHRC already has a remote-harness profile block, leaving it as-is"
    else
      printf '\n%s\n' "$ALIAS_BLOCK" >> "$BASHRC"
      echo "    added claude1..claude$ACCOUNT_COUNT aliases to $BASHRC"
    fi

    echo "    Log in to each account once, interactively, before starting the agent:"
    for i in $(seq 1 "$ACCOUNT_COUNT"); do
      echo "      source $BASHRC && claude$i    (then run /login)"
    done
  else
    echo "    Using a single account: whatever this machine is already logged in as (run 'claude' and /login if you haven't)."
  fi
fi

TSX_BIN="$REPO_ROOT/node_modules/.bin/tsx"
NODE_BIN="$(command -v node)"

echo "==> Installing systemd service"
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Remote Harness agent (Claude Code remote control)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$AGENT_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$NODE_BIN $TSX_BIN $AGENT_DIR/src/index.ts
Restart=always
RestartSec=3
User=$(whoami)
# Hardening: the agent needs the network, its own data and the workspace, not the rest of the system.
PrivateTmp=true
ProtectSystem=full
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "==> Done. Check status with:"
echo "    systemctl status $SERVICE_NAME"
echo "    journalctl -u $SERVICE_NAME -f"
