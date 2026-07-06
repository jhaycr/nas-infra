#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Backup-gated arbitrary write on the HA box, for changes that aren't the
# managed YAML push (add-on options, /config file surgery, ha CLI mutations).
# Takes a backup FIRST, always. Use --full when the command touches add-ons
# or their data (Z2M /config/zigbee2mqtt, Z-Wave, Mosquitto, `ha addons ...`).
#
#   ha-exec.sh '<command>'                    # dry run: show what would run
#   ha-exec.sh --confirm '<command>'          # partial backup, then run
#   ha-exec.sh --confirm --full '<command>'   # full backup, then run
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

CONFIRM=false
SCOPE=""
while [ $# -gt 1 ]; do
  case "$1" in
    --confirm) CONFIRM=true; shift ;;
    --full)    SCOPE="--full"; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done
CMD="${1:?Usage: ha-exec.sh [--confirm] [--full] '<remote command>'}"

# Nudge toward --full when the command clearly targets add-ons.
if [ -z "$SCOPE" ] && echo "$CMD" | grep -qE 'ha (addons|apps)|/addon_configs|zigbee2mqtt|zwave|mosquitto'; then
  echo "NOTE: command appears to touch add-ons — consider --full so the backup includes add-on data."
fi

section "Command to run on oracle"
echo "$CMD"

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would: take ${SCOPE:-partial} backup, then run the command above."
  echo "Re-run with --confirm AFTER the user has approved."
  exit 0
fi

take_backup $SCOPE

section "Executing"
oracle_ssh "$CMD"
RC=$?
echo
echo "Exit code: $RC"
exit $RC
