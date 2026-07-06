#!/usr/bin/env bash
# READ-ONLY. Tail logs: logs.sh [core|z2m|zwave|mosquitto|matter|otbr] [lines]
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

TARGET="${1:-core}"
LINES="${2:-100}"

case "$TARGET" in
  core)      CMD="ha core logs" ;;
  z2m)       CMD="ha addons logs 45df7312_zigbee2mqtt" ;;
  zwave)     CMD="ha addons logs core_zwave_js" ;;
  mosquitto) CMD="ha addons logs core_mosquitto" ;;
  matter)    CMD="ha addons logs core_matter_server" ;;
  otbr)      CMD="ha addons logs core_openthread_border_router" ;;
  *) echo "Usage: logs.sh [core|z2m|zwave|mosquitto|matter|otbr] [lines]" >&2; exit 2 ;;
esac

section "Logs: $TARGET (last $LINES lines)"
oracle_ssh "$CMD" | tail -n "$LINES"
