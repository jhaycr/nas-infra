#!/usr/bin/env bash
# Read-only inspection of the Hermes agent on smith (192.168.1.61).
# Fixed subcommands only — safe to allowlist as a whole.
#
# Usage: inspect.sh <subcommand> [args]
#   status              container/service state + uptime
#   agent-log [N]       last N lines (default 100) of /opt/data/logs/agent.log
#   errors [N]          last N lines of /opt/data/logs/errors.log
#   tool-usage [KB]     tool-call tally over the last KB (default 500) of agent.log
#   sessions            recent session activity (state.db mtimes + log timestamps)
#   workspace           git status/branch of both workspace clones
#   file <path>         cat a file inside the container (read-only)
set -euo pipefail

SSH=(ssh -i "$HOME/.ssh/ansible" -o BatchMode=yes -o ConnectTimeout=10 ansible@192.168.1.61)
IN=(sudo podman exec hermes-josh)

sub="${1:-}"; shift || true
case "$sub" in
  status)
    "${SSH[@]}" 'systemctl is-active podman-hermes-josh && sudo podman ps --filter name=hermes-josh --format "{{.Status}}" && sudo podman exec hermes-josh sh -c "ps aux | grep -c \"[h]ermes\""'
    ;;
  agent-log)
    n="${1:-100}"
    "${SSH[@]}" "${IN[*]} sh -c 'tail -n $n /opt/data/logs/agent.log'"
    ;;
  errors)
    n="${1:-50}"
    "${SSH[@]}" "${IN[*]} sh -c 'tail -n $n /opt/data/logs/errors.log'"
    ;;
  tool-usage)
    kb="${1:-500}"
    "${SSH[@]}" "${IN[*]} sh -c 'tail -c $((kb*1024)) /opt/data/logs/agent.log'" \
      | grep -oE '"(tool_name|tool|name)": ?"[A-Za-z0-9_]+"' | sort | uniq -c | sort -rn | head -20
    ;;
  sessions)
    "${SSH[@]}" "${IN[*]} sh -c 'ls -lt /opt/data/state.db* 2>/dev/null; tail -n 5 /opt/data/logs/agent.log | cut -c1-160'"
    ;;
  workspace)
    "${SSH[@]}" "${IN[*]} sh -c 'for r in /workspace/*/; do [ -d \$r/.git ] && echo \"== \$r\" && git -C \$r status -sb | head -5; done'"
    ;;
  file)
    path="${1:?file needs a path}"
    "${SSH[@]}" "${IN[*]} sh -c 'cat $(printf '%q' "$path")'"
    ;;
  *)
    sed -n '2,12p' "$0" >&2
    exit 2
    ;;
esac
