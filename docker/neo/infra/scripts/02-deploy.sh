#!/usr/bin/env bash
# Run this script from trinity, inside the nas-infra repo root.
# Prepares neo (clone, secrets) and installs Galaxy deps locally.
# After this, run 'make neo-docker' from trinity, then 02b-galaxy.sh.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
VAULT_KEY_SRC="$(dirname "$REPO_ROOT")/.ansible-vault.key"
NEO_USER="user0"
NEO_HOST="neo"
NEO_REPO_DIR="/home/$NEO_USER/code/gitea-working-clones/nas-infra"
NEO_SECRETS_DIR="/home/$NEO_USER/.secrets"

cd "$REPO_ROOT"

# --- Clone repo on neo first (group_vars/ dirs must exist before symlinking) ---
echo "=== [neo] Ensuring repo is cloned ==="
ssh "$NEO_USER@$NEO_HOST" "
  if [ -d '$NEO_REPO_DIR' ] && [ ! -w '$NEO_REPO_DIR' ]; then
    echo '  ERROR: $NEO_REPO_DIR exists but is not writable by $USER.'
    echo '  Run: sudo rm -rf $NEO_REPO_DIR   (then re-run 01-setup-neo.sh first)'
    exit 1
  fi
  if [ ! -d '$NEO_REPO_DIR/.git' ]; then
    rm -rf '$NEO_REPO_DIR'
    git clone https://github.com/jhaycr/nas-infra '$NEO_REPO_DIR'
    echo '  Cloned nas-infra to $NEO_REPO_DIR'
  else
    echo '  Repo already exists — skipping clone.'
  fi
"

# --- Copy vault key ---
echo "=== [trinity → neo] Copying vault key ==="
if [ ! -f "$VAULT_KEY_SRC" ]; then
  echo "  ERROR: Vault key not found at $VAULT_KEY_SRC" >&2
  exit 1
fi
# Guard: Docker may have created the destination as a directory on a previous run
ssh "$NEO_USER@$NEO_HOST" "
  [ -d '$NEO_SECRETS_DIR/.ansible-vault.key' ] && rm -rf '$NEO_SECRETS_DIR/.ansible-vault.key' || true
"
scp "$VAULT_KEY_SRC" "$NEO_USER@$NEO_HOST:$NEO_SECRETS_DIR/.ansible-vault.key"
ssh "$NEO_USER@$NEO_HOST" "chmod 600 '$NEO_SECRETS_DIR/.ansible-vault.key'"
echo "  Copied to $NEO_HOST:$NEO_SECRETS_DIR/.ansible-vault.key"

# --- Copy vault files and create symlinks ---
echo "=== [trinity → neo] Copying vault files ==="
for vault_link in group_vars/*/vault.yml; do
  host=$(basename "$(dirname "$vault_link")")
  actual_file=$(readlink -f "$vault_link")
  neo_secret="$NEO_SECRETS_DIR/$host.vault.yml"
  neo_link="$NEO_REPO_DIR/group_vars/$host/vault.yml"

  echo "  [$host] $actual_file → neo:$neo_secret"
  scp "$actual_file" "$NEO_USER@$NEO_HOST:$neo_secret"
  ssh "$NEO_USER@$NEO_HOST" "
    chmod 600 '$neo_secret'
    ln -sf '$neo_secret' '$neo_link'
  "
done
echo "  Vault symlinks created in $NEO_REPO_DIR/group_vars/"

# --- Install Galaxy deps locally (trinity) ---
echo "=== [trinity] Installing Galaxy collections and roles ==="
make reqs

echo ""
echo "Done. Next:"
echo "  1. Commit any pending work, then: make neo-docker"
echo "  2. Run scripts/02b-galaxy.sh"
