#!/bin/bash
# One-time: register YOUR admin account (@josh) on continuwuity.
#
# continuwuity ignores the configured registration token until the first
# account is made with the auto-generated *bootstrap* token it prints to its
# logs. That first account becomes the server admin — so this must be you, not
# the bot. Run this in your own terminal (it prompts for a password you choose).
#
#   bash bootstrap-register-josh.sh [username]     # default username: josh
set -euo pipefail

HS=${HS:-http://192.168.1.3:8014}
NEO=${NEO:-ansible@192.168.1.3}
USER=${1:-josh}
command -v jq >/dev/null || { echo "jq required"; exit 1; }

echo "Fetching the current bootstrap token from continuwuity logs..."
TOKEN=$(ssh "$NEO" 'sudo docker logs continuwuity 2>&1' \
          | sed 's/\x1b\[[0-9;]*m//g' \
          | grep -oiE 'using the registration token[[:space:]]+[A-Za-z0-9]+' \
          | tail -1 | awk '{print $NF}')
if [ "${#TOKEN}" -lt 8 ]; then
  echo "No valid bootstrap token in logs (got '${TOKEN:-}') — server may already be bootstrapped."
  exit 1
fi
echo "  got it (len ${#TOKEN})"

read -rsp "Choose a password for @$USER: " PW; echo
[ -n "$PW" ] || { echo "empty password, aborting"; exit 1; }
read -rsp "Confirm password: " PW2; echo
[ "$PW" = "$PW2" ] || { echo "passwords do not match, aborting"; exit 1; }

reg() { curl -s "$HS/_matrix/client/v3/register" -H 'Content-Type: application/json' -d "$1"; }

SESS=$(reg "$(jq -nc --arg u "$USER" --arg p "$PW" '{username:$u,password:$p}')" | jq -r '.session // empty')
[ -n "$SESS" ] || { echo "Could not open a registration session."; exit 1; }

RESP=$(reg "$(jq -nc --arg u "$USER" --arg p "$PW" --arg t "$TOKEN" --arg s "$SESS" \
        '{username:$u,password:$p,auth:{type:"m.login.registration_token",token:$t,session:$s}}')")

echo "$RESP" | jq -r 'if .user_id then "OK  registered \(.user_id) (this account is the server admin)"
                      else "ERR \(.errcode // "?") \(.error // "unknown")" end'
