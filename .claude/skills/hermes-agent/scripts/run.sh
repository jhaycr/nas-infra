#!/usr/bin/env bash
# One-shot task through the Hermes agent on smith (josh profile).
# Usage: run.sh [-w workspace] "task text"
#   -w workspace: start Hermes inside /workspace/<workspace> (or an absolute
#      path) so that repo's CLAUDE.md/AGENTS.md auto-load. Use for any task
#      that works on a clone (home-assistant-config, nas-infra).
# Output: Hermes's final answer on stdout. Agent loops can take minutes.
set -euo pipefail

workspace=""
if [ "${1:-}" = "-w" ]; then
  workspace="${2:?-w needs a workspace name}"
  shift 2
fi

if [ $# -eq 0 ]; then
  echo "usage: $0 [-w workspace] \"task text\"" >&2
  exit 2
fi

# %q-quote so the task survives the remote shell unmangled.
if [ -n "$workspace" ]; then
  exec ssh -i ~/.ssh/ansible -o BatchMode=yes ansible@192.168.1.61 \
    hermes-in "$workspace" -z "$(printf '%q' "$*")"
else
  exec ssh -i ~/.ssh/ansible -o BatchMode=yes ansible@192.168.1.61 \
    hermes -z "$(printf '%q' "$*")"
fi
