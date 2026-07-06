#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Terminates a stuck snapraid-runner process tree (runner + snapraid child + cron sh wrapper).
# Dry-run by default: shows what would be killed and exits.
#
#   kill-stuck-snapraid.sh                 # dry run (safe, default)
#   kill-stuck-snapraid.sh --confirm       # kill stuck SCRUB/TOUCH/other read-only ops
#   kill-stuck-snapraid.sh --confirm --allow-sync   # additionally allow killing a running SYNC
#
# Safety notes:
# - snapraid scrub/status/touch only READ the array; killing them is harmless.
# - snapraid sync writes parity. SnapRAID is crash-safe (interrupted syncs resume), but
#   killing a sync still requires --allow-sync and an explicit user OK.
# - Uses SIGTERM only. Never SIGKILL — snapraid cleans up its flock on TERM.
source "$(dirname "${BASH_SOURCE[0]}")/../inspect/_lib.sh"

CONFIRM=false
ALLOW_SYNC=false
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM=true ;;
    --allow-sync) ALLOW_SYNC=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

section "Current snapraid process tree on neo"
PROCS="$(neo_shell "ps -eo pid,stat,etime,time,args | grep -iE 'snapraid' | grep -v grep")"
echo "$PROCS"

if ! echo "$PROCS" | grep -qE '[0-9]'; then
  echo "Nothing to kill."
  exit 0
fi

if echo "$PROCS" | grep -qE 'snapraid sync|snapraid.*[^-]sync ' && ! $ALLOW_SYNC; then
  echo
  echo "REFUSING: a 'snapraid sync' is running. Killing sync needs --allow-sync"
  echo "(crash-safe by design, but get explicit user approval first)."
  exit 3
fi

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would send SIGTERM to the PIDs above (runner tree + snapraid child)."
  echo "Re-run with --confirm AFTER the user has approved."
  exit 0
fi

section "Sending SIGTERM to snapraid process tree"
neo_shell '
PIDS=$(ps -eo pid,args | grep -iE "snapraid" | grep -v grep | awk "{print \$1}")
echo "Killing: $PIDS"
kill $PIDS 2>&1
sleep 5
REMAIN=$(ps -eo pid,args | grep -iE "snapraid" | grep -v grep)
if [ -n "$REMAIN" ]; then echo "STILL RUNNING (may take time to unwind blocked I/O):"; echo "$REMAIN"; else echo "All snapraid processes terminated."; fi
ls -la /var/snapraid.content.lock 2>/dev/null || echo "Lock file gone."'

echo
echo "NOTE: if a process stays in D (uninterruptible I/O) state, it is blocked in the kernel"
echo "on a failing disk and will exit when the I/O request times out. Do NOT use kill -9."
