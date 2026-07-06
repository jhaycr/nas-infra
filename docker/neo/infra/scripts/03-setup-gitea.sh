#!/usr/bin/env bash
# Run this script from trinity (or any host that can reach neo) AFTER completing
# the Gitea setup wizard at http://192.168.1.3:3105.
set -euo pipefail

GITEA_URL="http://192.168.1.3:3105"

read -rp "Gitea admin username: " GITEA_USER
read -rsp "Gitea admin password: " GITEA_PASS; echo
read -rsp "GitHub token (repo scope, for mirror auth — leave blank for public repo): " GITHUB_TOKEN; echo

echo "=== Creating nas-infra mirror in Gitea ==="

PAYLOAD=$(jq -n \
  --arg clone_addr "https://github.com/jhaycr/nas-infra" \
  --arg auth_token "$GITHUB_TOKEN" \
  --arg repo_name "nas-infra" \
  --arg repo_owner "$GITEA_USER" \
  '{
    clone_addr: $clone_addr,
    auth_token: $auth_token,
    mirror: true,
    mirror_interval: "1m0s",
    private: false,
    repo_name: $repo_name,
    repo_owner: $repo_owner
  }')

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GITEA_URL/api/v1/repos/migrate" \
  -u "$GITEA_USER:$GITEA_PASS" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 201 ]; then
  REPO_URL=$(echo "$BODY" | jq -r '.html_url')
  echo "  Mirror created: $REPO_URL"
  echo "  Sync interval: 1m0s"
  echo ""
  echo "  Semaphore internal URL: http://gitea-server:3000/$GITEA_USER/nas-infra"
else
  echo "  Error (HTTP $HTTP_CODE): $BODY"
  exit 1
fi

echo ""
echo "Done. Next steps:"
echo "  1. Run 04-setup-semaphore.sh"
