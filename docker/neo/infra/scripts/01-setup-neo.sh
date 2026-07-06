#!/usr/bin/env bash
# Run this script ON neo (directly or via SSH from trinity):
#   ssh user0@neo 'bash -s' < scripts/01-setup-neo.sh
#
# Creates all directories and placeholder files that Docker bind mounts require.
# Must be run BEFORE 02-deploy.sh so Docker doesn't create these paths as root.
set -euo pipefail

NEO_USER="user0"
SECRETS_DIR="/home/$NEO_USER/.secrets"
WORKING_CLONE_DIR="/home/$NEO_USER/code/gitea-working-clones"
GITEA_REPOS_DIR="/home/$NEO_USER/code/gitea-repos"

echo "=== [neo] Checking for root-owned paths ==="
for dir in "$SECRETS_DIR" "$WORKING_CLONE_DIR" "$GITEA_REPOS_DIR"; do
  if [ -e "$dir" ] && [ ! -w "$dir" ]; then
    echo "  ERROR: $dir exists but is not writable by $USER (likely owned by root)."
    echo "  Fix with: sudo chown -R $USER:$USER $dir"
    exit 1
  fi
done
echo "  OK"

echo "=== [neo] Creating directory structure ==="
mkdir -p "$WORKING_CLONE_DIR/nas-infra"
mkdir -p "$GITEA_REPOS_DIR"
echo "  $WORKING_CLONE_DIR/nas-infra"
echo "  $GITEA_REPOS_DIR"

if [ ! -d "$SECRETS_DIR" ]; then
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$SECRETS_DIR"
fi
echo "  $SECRETS_DIR"

# Pre-create the vault key as an empty file so Docker doesn't create it as a
# directory when the Semaphore container starts with the bind mount.
VAULT_KEY_FILE="$SECRETS_DIR/.ansible-vault.key"
if [ -d "$VAULT_KEY_FILE" ]; then
  echo "  Removing leftover directory at $VAULT_KEY_FILE (created by Docker on a previous run)"
  rm -rf "$VAULT_KEY_FILE"
fi
if [ ! -f "$VAULT_KEY_FILE" ]; then
  touch "$VAULT_KEY_FILE"
  chmod 600 "$VAULT_KEY_FILE"
  echo "  Created placeholder $VAULT_KEY_FILE"
fi

echo ""
echo "Done. Run 02-deploy.sh from trinity next."
