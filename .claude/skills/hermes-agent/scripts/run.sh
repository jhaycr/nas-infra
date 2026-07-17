#!/usr/bin/env bash
# One-shot task through the Hermes agent on smith (josh profile).
# Usage: run.sh [-w workspace] "task text"
#   -w workspace: start Hermes inside /workspace/<workspace> (or an absolute
#      path) so that repo's CLAUDE.md/AGENTS.md auto-load. Use for any task
#      that works on a clone (home-assistant-config, nas-infra).
# Output: Hermes's final answer on stdout; a token-usage summary on stderr
# (written via --usage-file inside the container, for spend evaluation).
# Agent loops can take minutes.
set -euo pipefail

SSH=(ssh -i "$HOME/.ssh/ansible" -o BatchMode=yes ansible@192.168.1.61)

workspace=""
if [ "${1:-}" = "-w" ]; then
  workspace="${2:?-w needs a workspace name}"
  shift 2
fi

if [ $# -eq 0 ]; then
  echo "usage: $0 [-w workspace] \"task text\"" >&2
  exit 2
fi

# Usage file lives under /opt/data (always agent-writable); unique per run.
usage_file="/opt/data/usage-oneshot-$$-$(date +%s).json"

# %q-quote so the task survives the remote shell unmangled.
task_q="$(printf '%q' "$*")"

rc=0
if [ -n "$workspace" ]; then
  "${SSH[@]}" hermes-in "$workspace" -z "$task_q" --usage-file "$usage_file" || rc=$?
else
  "${SSH[@]}" hermes -z "$task_q" --usage-file "$usage_file" || rc=$?
fi

# Best-effort usage report to stderr; never fail the run over it.
"${SSH[@]}" "sudo podman exec hermes-josh sh -c 'cat $usage_file 2>/dev/null && rm -f $usage_file'" >&2 || true

exit "$rc"
