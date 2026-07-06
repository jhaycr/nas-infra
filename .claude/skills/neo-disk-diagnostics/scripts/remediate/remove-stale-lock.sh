#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Removes /var/snapraid.content.lock ONLY if no snapraid process is running.
# Usually unnecessary: snapraid uses flock, so the lock releases when the holder dies.
# Dry-run by default.
#
#   remove-stale-lock.sh              # dry run
#   remove-stale-lock.sh --confirm    # actually remove (after user approval)
source "$(dirname "${BASH_SOURCE[0]}")/../inspect/_lib.sh"

CONFIRM=false
[ "${1:-}" = "--confirm" ] && CONFIRM=true

section "Checking for running snapraid processes"
PROCS="$(neo_shell "ps -eo pid,args | grep -E '[s]napraid' || true")"
if echo "$PROCS" | grep -qE '[0-9]'; then
  echo "$PROCS"
  echo
  echo "REFUSING: snapraid is running — the lock is NOT stale. Use kill-stuck-snapraid.sh first."
  exit 3
fi
echo "No snapraid processes running."

section "Lock file"
neo_shell "ls -la /var/snapraid.content.lock 2>/dev/null || echo ABSENT"

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would: rm /var/snapraid.content.lock"
  echo "Re-run with --confirm AFTER the user has approved."
  exit 0
fi

neo_shell "rm -v /var/snapraid.content.lock 2>&1 || echo 'Nothing to remove.'"
