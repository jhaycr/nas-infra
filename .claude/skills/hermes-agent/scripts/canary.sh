#!/usr/bin/env bash
# Canary for the Hermes environment on smith. Run after every `make smith`,
# image digest bump, or guardrail change — catches the uid/env/mount
# regression class in about a minute, before a real task hits it.
# Deterministic checks only (no LLM call, no spend).
set -euo pipefail

SSH=(ssh -i "$HOME/.ssh/ansible" -o BatchMode=yes -o ConnectTimeout=10 ansible@192.168.1.61)

fail=0
check() { # name, command run inside the container as the agent user
  local name="$1" cmd="$2"
  if "${SSH[@]}" "sudo podman exec hermes-josh su hermes -s /bin/sh -c $(printf '%q' "$cmd")" >/dev/null 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name"; fail=1
  fi
}

check "cli-boots"            "hermes --version"
check "safe-root-env"        "env | grep -q '^HERMES_WRITE_SAFE_ROOT=/opt/data:/workspace$'"
check "workspace-writable"   "touch /workspace/.canary && rm /workspace/.canary"
check "ha-clone-writable"    "touch /workspace/home-assistant-config/.canary && rm /workspace/home-assistant-config/.canary"
check "nas-clone-writable"   "touch /workspace/nas-infra/.canary && rm /workspace/nas-infra/.canary"
check "ha-dev-cfg-writable"  "touch /workspace/ha-dev-config/.canary && rm /workspace/ha-dev-config/.canary"
check "rules-mounted"        "grep -q 'Turn discipline' /workspace/WORKFLOW.md"
check "rules-immutable"      "! sh -c 'echo x >> /workspace/WORKFLOW.md' 2>/dev/null"
check "ha-agents-md"         "grep -q 'ha-dev' /workspace/home-assistant-config/AGENTS.md"
check "nas-agents-md"        "grep -q 'For Hermes' /workspace/nas-infra/AGENTS.md"
check "ha-dev-tool"          "/workspace/bin/ha-dev check | grep -q valid"
check "compose-check-tool"   "/workspace/bin/compose-check /workspace/nas-infra/docker/neo/media-server/libation/docker-compose.yml.j2"
check "git-fetch-ha"         "git -C /workspace/home-assistant-config fetch origin"
check "git-fetch-nas"        "git -C /workspace/nas-infra fetch origin"
check "deploy-key-readable"  "test -r /etc/hermes/ha-config-deploy.key"

exit "$fail"
