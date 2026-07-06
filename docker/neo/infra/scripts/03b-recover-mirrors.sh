#!/usr/bin/env bash
# Recovers all Gitea mirrors after git data loss.
# Deletes each broken repo entry and re-creates it as a pull mirror.
# Run from trinity after the Gitea stack is healthy.
#
# Requires: curl, jq
set -euo pipefail

GITEA_URL="http://192.168.1.3:3105"

read -rp "Gitea admin username: " GITEA_USER
read -rsp "Gitea admin password: " GITEA_PASS; echo

# owner  repo-name  source-url
REPOS=(
  "backups-drm  AaxAudioConverter       https://github.com/audiamus/AaxAudioConverter.git"
  "books        ansible-for-devops      https://github.com/geerlingguy/ansible-for-devops.git"
  "books        ansible-for-devops-manuscript https://github.com/geerlingguy/ansible-for-devops-manuscript.git"
  "backups-drm  BookLibConnect          https://github.com/audiamus/BookLibConnect.git"
  "josh         DeDRM_tools             https://github.com/noDRM/DeDRM_tools.git"
  "backups-drm  DeDRM_tools             https://github.com/apprenticeharper/DeDRM_tools.git"
  "backups-drm  Flipper                 https://github.com/UberGuidoZ/Flipper"
  "backups-drm  KeyDecoder              https://github.com/MaximeBeasse/KeyDecoder"
  "backups-drm  Libation                https://github.com/rmcrackan/Libation.git"
  "josh         nas-infra               https://github.com/jhaycr/nas-infra.git"
  "backups-drm  ripme                   https://github.com/RipMeApp/ripme.git"
  "backups-drm  youtube-dl              https://github.com/ytdl-org/youtube-dl"
  "backups-drm  yt-dlp                  https://github.com/yt-dlp/yt-dlp.git"
)

for entry in "${REPOS[@]}"; do
  read -r owner repo url <<< "$entry"
  echo "=== $owner/$repo ==="

  # Delete the broken entry (404 is fine — already gone)
  HTTP=$(curl -sf -w "%{http_code}" -o /dev/null -X DELETE \
    "$GITEA_URL/api/v1/repos/$owner/$repo" \
    -u "$GITEA_USER:$GITEA_PASS" || true)
  echo "  Deleted (HTTP ${HTTP:-???})"

  # Re-create as pull mirror
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "$GITEA_URL/api/v1/repos/migrate" \
    -u "$GITEA_USER:$GITEA_PASS" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg clone_addr "$url" \
      --arg repo_name  "$repo" \
      --arg repo_owner "$owner" \
      '{clone_addr: $clone_addr, mirror: true, mirror_interval: "1m0s",
        private: false, repo_name: $repo_name, repo_owner: $repo_owner}')")

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "  Created: $(echo "$BODY" | jq -r '.html_url')"
  else
    echo "  ERROR (HTTP $HTTP_CODE): $BODY"
  fi
  echo ""
done

echo "Done. Gitea will sync all mirrors in the background (1m interval)."
echo "Large repos (Flipper, yt-dlp) may take a while to fully clone."
