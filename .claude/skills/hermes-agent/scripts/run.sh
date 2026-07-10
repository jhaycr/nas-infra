#!/usr/bin/env bash
# One-shot task through the Hermes agent on smith (josh profile).
# Usage: run.sh "task text"
# Output: Hermes's final answer on stdout. Agent loops can take minutes.
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: $0 \"task text\"" >&2
  exit 2
fi

# %q-quote so the task survives the remote shell unmangled.
exec ssh -i ~/.ssh/ansible -o BatchMode=yes ansible@192.168.1.61 \
  hermes -z "$(printf '%q' "$*")"
