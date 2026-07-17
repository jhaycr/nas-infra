#!/bin/sh
# ha-dev — deterministic dev-HA test loop for the Hermes agent.
# Root-owned, deployed from nix/smith/ha-dev.sh (nas-infra) via tmpfiles.
# Wraps auth + the API calls the WORKFLOW.md test loop needs, so the agent
# spends zero turns on login flows or curl syntax.
#
# Usage: /workspace/bin/ha-dev <cmd> [args]
#   check                       validate config (POST core/check_config)
#   reload <domain>             automation|script|scene|template reload
#   restart                     restart core, poll until API is back
#   deploy <file>...            copy files into /workspace/ha-dev-config/
#   seed <entity_id> <state> [attrs-json]   set a state (fires state_changed)
#   state <entity_id>           get one entity's state JSON
#   states [grep]               list entity_id+state, optionally filtered
#   call <domain> <service> [data-json]     call a service on dev HA
#   logbook [minutes]           logbook entries for the last N minutes (default 15)
#   errors                      tail of the dev HA error log
#   api <GET|POST> <path> [json]            raw authed API call
set -eu

BASE="${HA_DEV_URL:-http://127.0.0.1:8124}"
CONF=/workspace/ha-dev-config
TOK_CACHE="/tmp/.ha-dev-token"

_py() { python3 -c "$1" "$@"; }

_mint_token() {
  python3 - "$BASE" "${HA_DEV_USERNAME:?HA_DEV_USERNAME not set}" "${HA_DEV_PASSWORD:?HA_DEV_PASSWORD not set}" <<'EOF'
import json, sys, urllib.request, urllib.parse
base, user, pw = sys.argv[1:4]
def post(path, data, form=False):
    body = urllib.parse.urlencode(data).encode() if form else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=body)
    if not form: req.add_header("Content-Type", "application/json")
    return json.load(urllib.request.urlopen(req, timeout=15))
cid = base + "/"
flow = post("/auth/login_flow", {"client_id": cid, "handler": ["homeassistant", None], "redirect_uri": cid})
res = post("/auth/login_flow/" + flow["flow_id"], {"client_id": cid, "username": user, "password": pw})
tok = post("/auth/token", {"grant_type": "authorization_code", "code": res["result"], "client_id": cid}, form=True)
print(tok["access_token"])
EOF
}

_token() {
  # Cache for 25 min (tokens live ~30).
  if [ -f "$TOK_CACHE" ] && [ -n "$(find "$TOK_CACHE" -mmin -25 2>/dev/null)" ]; then
    cat "$TOK_CACHE"; return
  fi
  t=$(_mint_token)
  umask 077; printf '%s' "$t" > "$TOK_CACHE"
  printf '%s' "$t"
}

_api() { # method path [json-body]
  m="$1"; p="$2"; body="${3:-}"
  tok=$(_token)
  if [ -n "$body" ]; then
    curl -sS -X "$m" -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      --data "$body" "$BASE$p"
  else
    curl -sS -X "$m" -H "Authorization: Bearer $tok" "$BASE$p"
  fi
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  check)   _api POST /api/config/core/check_config ;;
  reload)  d="${1:?reload needs a domain}"; _api POST "/api/services/$d/reload" '{}' ;;
  restart)
    _api POST /api/services/homeassistant/restart '{}' >/dev/null 2>&1 || true
    echo "restarting..."
    i=0
    while [ $i -lt 60 ]; do
      sleep 3; i=$((i+1))
      if _api GET /api/ >/dev/null 2>&1; then echo "up after ~$((i*3))s"; exit 0; fi
    done
    echo "dev HA not back after 180s" >&2; exit 1
    ;;
  deploy)
    [ $# -gt 0 ] || { echo "deploy needs file(s)" >&2; exit 2; }
    for f in "$@"; do cp -v "$f" "$CONF/"; done
    ;;
  seed)
    e="${1:?seed needs entity_id}"; s="${2:?seed needs state}"; attrs="${3:-{\}}"
    _api POST "/api/states/$e" "{\"state\":\"$s\",\"attributes\":$attrs}"
    ;;
  state)   _api GET "/api/states/${1:?state needs entity_id}" ;;
  states)
    out=$(_api GET /api/states | python3 -c 'import json,sys; [print(e["entity_id"], e["state"]) for e in json.load(sys.stdin)]')
    if [ $# -gt 0 ]; then echo "$out" | grep -i "$1" || true; else echo "$out"; fi
    ;;
  call)
    d="${1:?call needs domain}"; s="${2:?call needs service}"; data="${3:-{\}}"
    _api POST "/api/services/$d/$s" "$data"
    ;;
  logbook)
    mins="${1:-15}"
    start=$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(minutes=$mins)).strftime('%Y-%m-%dT%H:%M:%S%z'))")
    _api GET "/api/logbook/$start"
    ;;
  errors)  _api GET /api/error_log | tail -n 60 ;;
  api)     _api "${1:?api needs method}" "${2:?api needs path}" "${3:-}" ;;
  *)
    sed -n '3,20p' "$0" >&2
    exit 2
    ;;
esac
