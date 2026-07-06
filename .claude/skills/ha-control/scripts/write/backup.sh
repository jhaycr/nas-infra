#!/usr/bin/env bash
# Take an HA backup now and prune old auto-backups. Safe to run anytime
# (creates a backup — it never modifies config).
#   backup.sh            # partial: HA config + database
#   backup.sh --full     # full: everything including add-ons (Z2M, Z-Wave, Mosquitto)
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

take_backup "${1:-}"
