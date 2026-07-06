#!/usr/bin/env bash
# Shared helpers for neo disk diagnostics. READ-ONLY.
# All host access goes through Ansible ad-hoc (connects as user 'ansible', becomes root).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
NEO_IP="192.168.1.3"
LOKI_URL="http://${NEO_IP}:3100"
GRAFANA_URL="http://${NEO_IP}:3000"

# Run a read-only shell command on neo as root via Ansible.
neo_shell() {
  (cd "$REPO_ROOT" && ansible neo -m shell -a "$1" --become 2>&1 | sed '1s/.*| \(CHANGED\|SUCCESS\|FAILED\).*//')
}

section() {
  printf '\n===== %s =====\n' "$1"
}
