#!/usr/bin/env bash
# One-line installer for the Remote Harness agent. Run on the VM you want to control:
#   curl -fsSL https://raw.githubusercontent.com/yashmishra2006/remote-harness-for-vms/main/packages/agent/bootstrap.sh | bash
#
# Clones (or updates) the repo, then hands off to the real installer at
# packages/agent/install.sh, which asks the setup questions and installs
# the systemd service.
set -euo pipefail

REPO_URL="https://github.com/yashmishra2006/remote-harness-for-vms.git"
INSTALL_DIR="${REMOTE_HARNESS_DIR:-$HOME/remote-harness-for-vms}"

echo "==> Checking git"
if ! command -v git >/dev/null 2>&1; then
  echo "git is required. Install it (e.g. 'sudo apt install git') and re-run."
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> Found existing checkout at $INSTALL_DIR, updating"
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "==> Cloning into $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

exec "$INSTALL_DIR/packages/agent/install.sh"
