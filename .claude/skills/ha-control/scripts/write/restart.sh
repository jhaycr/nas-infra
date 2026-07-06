#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Restarts HA core after a partial backup, then waits until it's healthy.
#   restart.sh              # dry run
#   restart.sh --confirm    # backup, restart, wait for healthy
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

CONFIRM=false
[ "${1:-}" = "--confirm" ] && CONFIRM=true

section "Current core state"
oracle_ssh "ha core info" | grep -E 'version|state|update_available'

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would: partial backup, then 'ha core restart', then wait for healthy."
  echo "Re-run with --confirm AFTER the user has approved."
  exit 0
fi

take_backup

section "Restarting HA core"
oracle_ssh "ha core restart"
wait_for_core
