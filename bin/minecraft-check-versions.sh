#!/bin/bash
# On-demand version-compatibility guardrail for the Minecraft stack
# (docker/neo/games/minecraft, docker/neo/games/minecraft-proxy).
#
# Single source of truth for pins is group_vars/neo/vars.yml -> minecraft_versions.
# This script never runs on a schedule and never retries a failed smoke test
# automatically - each invocation makes exactly one attempt per component and
# always tears down its own containers, pass or fail.
#
# Usage:
#   bin/minecraft-check-versions.sh                 # show current pins vs. latest upstream builds
#   bin/minecraft-check-versions.sh --test           # smoke-test the CURRENTLY pinned versions
#   bin/minecraft-check-versions.sh --test-latest     # smoke-test the newest available build of each pin
#   bin/minecraft-check-versions.sh --apply <file>    # write a validated pin set (see --test-latest output) into vars.yml
#
# Requires: docker (DOCKER_HOST defaults to unix:///var/run/docker.sock), python3, curl.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS_FILE="$REPO_ROOT/group_vars/neo/vars.yml"
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"

SMOKE_TIMEOUT=90   # seconds to wait for a container to reach a terminal state
POLL_INTERVAL=3

cleanup_containers=()
cleanup() {
  for c in "${cleanup_containers[@]:-}"; do
    [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

read_pins() {
  python3 - "$VARS_FILE" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
mv = data["minecraft_versions"]
for k, v in mv.items():
    print(f"{k}={v}")
PY
}

# Populate MV_* vars from the current pins (e.g. MV_VELOCITY_VERSION)
load_pins() {
  while IFS='=' read -r k v; do
    declare -g "MV_${k^^}=$v"
  done < <(read_pins)
}

latest_geyser_build() {  # $1 = geyser|floodgate, $2 = version
  curl -sf "https://download.geysermc.org/v2/projects/$1/versions/$2" \
    | python3 -c "import json,sys; print(sorted(json.load(sys.stdin)['builds'])[-1])"
}

latest_geyser_version() {  # $1 = geyser|floodgate
  curl -sf "https://download.geysermc.org/v2/projects/$1" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['versions'][-1])"
}

latest_velocity_build() {  # $1 = version line, e.g. 3.6.0-SNAPSHOT
  curl -sf "https://fill.papermc.io/v3/projects/velocity/versions/$1/builds" \
    | python3 -c "import json,sys; b=json.load(sys.stdin); print(max(b, key=lambda x: x['id'])['id'])"
}

show_status() {
  load_pins
  echo "Currently pinned (group_vars/neo/vars.yml):"
  echo "  velocity:  ${MV_VELOCITY_VERSION} build ${MV_VELOCITY_BUILD}"
  echo "  geyser:    ${MV_GEYSER_VERSION} build ${MV_GEYSER_BUILD}"
  echo "  floodgate: ${MV_FLOODGATE_VERSION} build ${MV_FLOODGATE_BUILD}"
  echo "  paper:     ${MV_PAPER}"
  echo "  via*:      ViaVersion ${MV_VIAVERSION} / ViaBackwards ${MV_VIABACKWARDS} / ViaRewind ${MV_VIAREWIND}"
  echo
  echo "Latest available upstream (not yet validated - use --test-latest to check compatibility):"
  local gv gb fb vb
  gv=$(latest_geyser_version geyser)
  gb=$(latest_geyser_build geyser "$gv")
  fb=$(latest_geyser_build floodgate "${MV_FLOODGATE_VERSION}")
  vb=$(latest_velocity_build "${MV_VELOCITY_VERSION}")
  echo "  velocity:  ${MV_VELOCITY_VERSION} build ${vb}"
  echo "  geyser:    ${gv} build ${gb}"
  echo "  floodgate: ${MV_FLOODGATE_VERSION} build ${fb}"
}

# Smoke-test the proxy: Velocity + Geyser + Floodgate.
# Never bind-mounts individual files into /server - single-file bind mounts
# break Geyser's atomic config save ("Device or resource busy") and that is
# NOT how the real compose file mounts anything (whole-dir mount only).
smoke_test_proxy() {
  local vv="$1" vb="$2" gv="$3" gb="$4" fv="$5" fb="$6"
  local name="mc-proxy-check-$$"
  cleanup_containers+=("$name")

  echo "--- proxy smoke test: velocity ${vv}-b${vb}, geyser ${gv}-b${gb}, floodgate ${fv}-b${fb} ---"
  docker run -d --name "$name" \
    -e TYPE=VELOCITY \
    -e VELOCITY_VERSION="$vv" \
    -e VELOCITY_BUILD_ID="$vb" \
    -e PLUGINS="https://download.geysermc.org/v2/projects/geyser/versions/${gv}/builds/${gb}/downloads/velocity
https://download.geysermc.org/v2/projects/floodgate/versions/${fv}/builds/${fb}/downloads/velocity" \
    itzg/mc-proxy >/dev/null

  local waited=0
  while [ "$waited" -lt "$SMOKE_TIMEOUT" ]; do
    if docker logs "$name" 2>&1 | grep -qE "Started Geyser on UDP port"; then
      echo "PASS: proxy booted cleanly."
      docker rm -f "$name" >/dev/null 2>&1
      return 0
    fi
    if docker logs "$name" 2>&1 | grep -qE "NoSuchMethodError|Couldn't pass ListenerBoundEvent|Disabling geyser"; then
      echo "FAIL: proxy crashed on startup. Last 30 log lines:"
      docker logs "$name" 2>&1 | tail -30
      return 1
    fi
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done
  echo "FAIL: proxy did not reach a clean startup within ${SMOKE_TIMEOUT}s. Last 30 log lines:"
  docker logs "$name" 2>&1 | tail -30
  return 1
}

# Smoke-test one Paper backend with the pinned Via* plugins (no proxy needed -
# this only checks that Paper + Via* load together without erroring).
smoke_test_paper() {
  local paper="$1" vv="$2" vbw="$3" vrw="$4"
  local name="mc-paper-check-$$"
  cleanup_containers+=("$name")

  echo "--- paper smoke test: paper ${paper}, viaversion ${vv}, viabackwards ${vbw}, viarewind ${vrw} ---"
  docker run -d --name "$name" \
    -e EULA=true -e TYPE=PAPER -e VERSION="$paper" -e ONLINE_MODE=false -e MEMORY=512M \
    -e PLUGINS="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/${vv}/PAPER/ViaVersion-${vv}.jar
https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/${vbw}/PAPER/ViaBackwards-${vbw}.jar
https://hangarcdn.papermc.io/plugins/ViaVersion/ViaRewind/versions/${vrw}/PAPER/ViaRewind-${vrw}.jar" \
    itzg/minecraft-server:2026.7.0 >/dev/null

  local waited=0
  while [ "$waited" -lt "$SMOKE_TIMEOUT" ]; do
    if docker logs "$name" 2>&1 | grep -qE '^\[[0-9:]+ INFO\]: Done \('; then
      echo "PASS: paper backend booted cleanly."
      docker rm -f "$name" >/dev/null 2>&1
      return 0
    fi
    if docker logs "$name" 2>&1 | grep -qE "Error occurred while enabling|could not load"; then
      echo "FAIL: a plugin failed to enable. Last 30 log lines:"
      docker logs "$name" 2>&1 | tail -30
      return 1
    fi
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done
  echo "FAIL: paper backend did not reach a clean startup within ${SMOKE_TIMEOUT}s. Last 30 log lines:"
  docker logs "$name" 2>&1 | tail -30
  return 1
}

apply_pins() {
  local vv="$1" vb="$2" gv="$3" gb="$4" fv="$5" fb="$6" paper="$7"
  python3 - "$VARS_FILE" "$vv" "$vb" "$gv" "$gb" "$fv" "$fb" "$paper" <<'PY'
import re, sys
path, vv, vb, gv, gb, fv, fb, paper = sys.argv[1:9]
text = open(path).read()
def sub(field, value, text):
    return re.sub(rf'({field}:\s*).*', rf'\g<1>"{value}"' if not str(value).isdigit() else rf'\g<1>{value}', text, count=1)
text = sub("velocity_version", vv, text)
text = sub("velocity_build", vb, text)
text = sub("geyser_version", gv, text)
text = sub("geyser_build", gb, text)
text = sub("floodgate_version", fv, text)
text = sub("floodgate_build", fb, text)
text = sub("paper", paper, text)
open(path, "w").write(text)
print(f"Wrote validated pins to {path}")
PY
}

cmd="${1:-status}"
case "$cmd" in
  status|--status|"")
    show_status
    ;;
  --test)
    load_pins
    smoke_test_proxy "${MV_VELOCITY_VERSION}" "${MV_VELOCITY_BUILD}" "${MV_GEYSER_VERSION}" "${MV_GEYSER_BUILD}" "${MV_FLOODGATE_VERSION}" "${MV_FLOODGATE_BUILD}"
    smoke_test_paper "${MV_PAPER}" "${MV_VIAVERSION}" "${MV_VIABACKWARDS}" "${MV_VIAREWIND}"
    ;;
  --test-latest)
    load_pins
    gv=$(latest_geyser_version geyser)
    gb=$(latest_geyser_build geyser "$gv")
    fb=$(latest_geyser_build floodgate "${MV_FLOODGATE_VERSION}")
    vb=$(latest_velocity_build "${MV_VELOCITY_VERSION}")
    if smoke_test_proxy "${MV_VELOCITY_VERSION}" "$vb" "$gv" "$gb" "${MV_FLOODGATE_VERSION}" "$fb"; then
      echo
      echo "Validated combo. To apply:"
      echo "  bin/minecraft-check-versions.sh --apply ${MV_VELOCITY_VERSION} $vb $gv $gb ${MV_FLOODGATE_VERSION} $fb ${MV_PAPER}"
    fi
    ;;
  --apply)
    shift
    if [ "$#" -ne 7 ]; then
      echo "Usage: $0 --apply <velocity_version> <velocity_build> <geyser_version> <geyser_build> <floodgate_version> <floodgate_build> <paper_version>" >&2
      exit 1
    fi
    apply_pins "$@"
    ;;
  *)
    echo "Unknown argument: $cmd" >&2
    echo "Usage: $0 [status|--test|--test-latest|--apply ...]" >&2
    exit 1
    ;;
esac
