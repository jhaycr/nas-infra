#!/usr/bin/env bash
# One-shot task through the Hermes agent on smith (josh profile).
# Usage: run.sh [-w workspace] [-m model] "task text"
#   -w workspace: start Hermes inside /workspace/<workspace> (or an absolute
#      path) so that repo's CLAUDE.md/AGENTS.md auto-load. Use for any task
#      that works on a clone (home-assistant-config, nas-infra).
#   -m model: override the profile's default model (OpenRouter id, e.g.
#      a cheaper one for mechanical tasks).
# Output: Hermes's final answer on stdout; token-usage JSON on stderr.
# Every run's usage is also appended to ~/.local/state/hermes-runs.jsonl
# (with timestamp + task hash) for spend/efficiency telemetry.
# Agent loops can take minutes.
set -euo pipefail

SSH=(ssh -i "$HOME/.ssh/ansible" -o BatchMode=yes ansible@192.168.1.61)
TELEMETRY="$HOME/.local/state/hermes-runs.jsonl"

workspace="" model=""
while [ $# -gt 0 ]; do
  case "$1" in
    -w) workspace="${2:?-w needs a workspace name}"; shift 2 ;;
    -m) model="${2:?-m needs a model id}"; shift 2 ;;
    *) break ;;
  esac
done

if [ $# -eq 0 ]; then
  echo "usage: $0 [-w workspace] [-m model] \"task text\"" >&2
  exit 2
fi

usage_file="/opt/data/usage-oneshot-$$-$(date +%s).json"
task_q="$(printf '%q' "$*")"

cmd=(hermes)
[ -n "$workspace" ] && cmd=(hermes-in "$workspace")
cmd+=(-z "$task_q" --usage-file "$usage_file")
[ -n "$model" ] && cmd+=(--model "$model")

rc=0
"${SSH[@]}" "${cmd[@]}" || rc=$?

# Usage report: stderr for the caller, plus a telemetry line on trinity.
usage_json="$("${SSH[@]}" "sudo podman exec hermes-josh sh -c 'cat $usage_file 2>/dev/null && rm -f $usage_file'" || true)"
if [ -n "$usage_json" ]; then
  echo "$usage_json" >&2
  mkdir -p "$(dirname "$TELEMETRY")"
  python3 - "$TELEMETRY" "$workspace" "$rc" <<EOF >> /dev/null 2>&1 || true
import json, sys, hashlib, datetime
usage = json.loads('''$usage_json''')
usage.update({
    "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "workspace": sys.argv[2] or None,
    "exit_code": int(sys.argv[3]),
    "task_sha": hashlib.sha256('''$task_q'''.encode()).hexdigest()[:12],
})
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(usage) + "\n")
EOF
fi

exit "$rc"
