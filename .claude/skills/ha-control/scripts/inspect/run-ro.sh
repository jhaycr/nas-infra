#!/usr/bin/env bash
# READ-ONLY escape hatch: run an arbitrary read-only command on the HA box.
#   run-ro.sh 'jq -r ".data.entries[].domain" /config/.storage/core.config_entries'
# Refuses commands containing write-ish patterns. This is a guardrail against
# accidents, not a security boundary — writes belong in scripts/write/*.
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

CMD="${1:?Usage: run-ro.sh '<remote command>'}"

# Stderr-only redirects are fine; strip them before the write-pattern check.
CHECK="${CMD//2>&1/}"
CHECK="${CHECK//2>\/dev\/null/}"

DENY_RE='(>|>>|\btee\b|\brm\b|\bcp\b|\bmv\b|\bmkdir\b|\btouch\b|\bchmod\b|\bchown\b|sed .*-i|\bapk\b|\bdd\b|\btruncate\b|\bln\b'
DENY_RE+='|ha core (restart|rebuild|stop|start|update|rollback)'
DENY_RE+='|ha (addons|apps) (restart|stop|start|update|install|uninstall|set-options|options)'
DENY_RE+='|ha backups (remove|restore)|ha host|ha os (update|import)|ha su)'

if echo "$CHECK" | grep -qE "$DENY_RE"; then
  echo "REFUSING: command matches a write pattern. Use scripts/write/ha-exec.sh (backup-gated) instead." >&2
  exit 3
fi

oracle_ssh "$CMD"
