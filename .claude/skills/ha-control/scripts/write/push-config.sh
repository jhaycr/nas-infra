#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Pushes the managed YAML config (files/home_assistant/) to the live HA box
# via `make oracle-push`. The site.yml pre_task takes a partial backup before
# the push, so this wrapper does not back up again. HA restarts only if a
# file actually changed (role handler).
#
#   push-config.sh              # dry run: diff repo files vs live /config
#   push-config.sh --confirm    # actually push (after user approval)
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

CONFIRM=false
[ "${1:-}" = "--confirm" ] && CONFIRM=true

MANAGED_FILES="automations scripts scenes configuration climate-dashboard"
LOCAL_DIR="$REPO_ROOT/files/home_assistant"

section "Diff: repo -> live /config"
CHANGES=0
for f in $MANAGED_FILES; do
  if ! DIFF="$(oracle_ssh "cat /config/${f}.yaml 2>/dev/null" | diff -u --label "live/${f}.yaml" - --label "repo/${f}.yaml" "$LOCAL_DIR/${f}.yaml")"; then
    CHANGES=$((CHANGES + 1))
    echo "$DIFF"
    echo
  fi
done
[ "$CHANGES" -eq 0 ] && echo "No differences — push would be a no-op (no restart would fire)."

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would: partial backup (site.yml pre_task) + make oracle-push ($CHANGES file(s) changed) + restart if changed."
  echo "Re-run with --confirm AFTER the user has approved."
  exit 0
fi

section "Pushing config (make oracle-push)"
(cd "$REPO_ROOT" && make oracle-push) || { echo "PUSH FAILED — check ansible output above." >&2; exit 1; }

if [ "$CHANGES" -gt 0 ]; then
  wait_for_core
fi
prune_backups
