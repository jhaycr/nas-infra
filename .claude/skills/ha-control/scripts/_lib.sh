#!/usr/bin/env bash
# Shared helpers for HA control (oracle / HA Green).
# All host access goes over SSH via the Terminal & SSH addon (root, key auth).
# The addon shell has `ha` CLI and `jq` but NO python3 — keep remote commands POSIX.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ORACLE_IP="192.168.1.152"
ORACLE_SSH_KEY="$HOME/.ssh/ansible"
BACKUP_KEEP=5   # retained auto-backups per prefix (agent-pre-write-*, pre-push-*)

oracle_ssh() {
  ssh -i "$ORACLE_SSH_KEY" -o ConnectTimeout=10 "root@${ORACLE_IP}" "$1"
}

section() {
  printf '\n===== %s =====\n' "$1"
}

# take_backup [--full]
# Takes a Supervisor backup and aborts the caller (exit 4) if it fails.
# Partial (--homeassistant: HA config + DB) by default; --full includes add-ons.
# `ha backups new` blocks until the backup completes and prints its slug.
take_backup() {
  local scope_flag="--folders homeassistant" scope_name="partial"
  if [ "${1:-}" = "--full" ]; then
    scope_flag=""
    scope_name="full"
  fi
  local name="agent-pre-write-$(date -u +%Y%m%d-%H%M%S)"

  section "Taking ${scope_name} backup: ${name}"
  local out
  out="$(oracle_ssh "ha backups new ${scope_flag} --name '${name}' --no-progress 2>&1")"
  echo "$out"
  if ! echo "$out" | grep -qE 'slug: "?[a-f0-9]'; then
    echo "ABORTING: backup did not complete (no slug returned). No write was performed." >&2
    exit 4
  fi
  prune_backups
}

# Keep the newest $BACKUP_KEEP backups per auto-backup prefix, remove the rest.
prune_backups() {
  section "Pruning auto-backups (keep ${BACKUP_KEEP} per prefix)"
  local prefix
  for prefix in agent-pre-write- pre-push-; do
    # `ha backups --raw-json` gives {slug,name,date,...}; sort newest first.
    oracle_ssh "ha backups --raw-json" \
      | jq -r --arg p "$prefix" \
          '.data.backups[] | select(.name | startswith($p)) | "\(.date)\t\(.slug)\t\(.name)"' \
      | sort -r | tail -n +$((BACKUP_KEEP + 1)) \
      | while IFS=$'\t' read -r _date slug name; do
          echo "Removing old backup: $name ($slug)"
          oracle_ssh "ha backups remove '$slug'" >/dev/null
        done
  done
  echo "Done."
}

# Poll until HA core reports healthy again (used after pushes/restarts).
wait_for_core() {
  section "Waiting for HA core to report healthy"
  local i
  for i in $(seq 1 30); do
    if oracle_ssh "ha core info --raw-json" 2>/dev/null | jq -e '.data.version' >/dev/null 2>&1; then
      echo "HA core is up (attempt $i)."
      return 0
    fi
    sleep 10
  done
  echo "WARNING: HA core did not report healthy after 5 minutes — check manually." >&2
  return 1
}
