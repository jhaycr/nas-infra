#!/usr/bin/env bash
# Run this script from trinity, inside the nas-infra repo root.
# Adds 'neo' as a git remote so you can push directly to neo over LAN.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
NEO_USER="user0"
NEO_HOST="neo"
REPO_PATH="/home/$NEO_USER/code/gitea-working-clones/nas-infra"

cd "$REPO_ROOT"

echo "=== [trinity] Configuring git remotes ==="

if git remote get-url neo &>/dev/null; then
  echo "  Remote 'neo' already exists: $(git remote get-url neo)"
else
  git remote add neo "$NEO_USER@$NEO_HOST:$REPO_PATH"
  echo "  Added remote 'neo' → $NEO_USER@$NEO_HOST:$REPO_PATH"
fi

echo ""
echo "Git remotes:"
git remote -v

echo ""
echo "Usage:"
echo "  Online  (push to GitHub, Gitea mirrors automatically):"
echo "    git push origin main"
echo ""
echo "  Offline (push directly to neo, Semaphore picks it up immediately):"
echo "    git push neo main"
echo ""
echo "  Sync back to GitHub when back online (from trinity):"
echo "    git push origin main"
