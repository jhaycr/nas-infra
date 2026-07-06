#!/usr/bin/env bash
# READ-ONLY. Overall health snapshot: core, OS, add-ons, supervisor issues, backups.
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

section "Core"
oracle_ssh "ha core info" | grep -E 'version|update_available|state|machine'

section "OS"
oracle_ssh "ha os info" | grep -E 'version|update_available|board|boot:'

section "Add-ons"
oracle_ssh "ha addons 2>/dev/null" | grep -E '^  (name|state|version):' | paste - - -

section "Supervisor-detected issues"
oracle_ssh "ha resolution info" | head -40

section "Backups (newest 10)"
oracle_ssh "ha backups --raw-json" \
  | jq -r '.data.backups | sort_by(.date) | reverse | .[:10][] | "\(.date)  \(.type)  \(.name)  (\(.slug))"'
