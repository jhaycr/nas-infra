#!/usr/bin/env bash
# Open a GitHub PR for a hermes/* branch, from trinity (smith has no GitHub
# token by design — Hermes hands back PR title/body, this closes the loop).
#
# Usage: pr-create.sh <repo> <branch> <title-file-or-title> [body-file]
#   repo:   home-assistant-config | nas-infra (owner jhaycr assumed)
#   branch: e.g. hermes/clear-alerts (must already be pushed)
#   If body-file is omitted, the body is read from stdin.
set -euo pipefail

repo="${1:?repo (home-assistant-config|nas-infra)}"
branch="${2:?branch (hermes/<topic>)}"
title="${3:?title text or @file}"
body_file="${4:-}"

case "$title" in @*) title="$(cat "${title#@}")" ;; esac

args=(--repo "jhaycr/$repo" --base main --head "$branch" --title "$title")
if [ -n "$body_file" ]; then
  args+=(--body-file "$body_file")
else
  args+=(--body-file -)
fi

exec gh pr create "${args[@]}"
