#!/bin/bash
# resync-baibot.sh — workaround for continuwuity bug #779.
#
# THE BUG: when a Matrix client joins a room, continuwuity sometimes fails to
# send that room's state (power levels, etc.) down /sync — "a lack of
# transactions in the DB means a /sync during a join hits broken invariants"
# (https://forgejo.ellis.link/continuwuation/continuwuity/issues/779). baibot
# is the joining client, so it never gets the room's power levels and then:
#   - in an ENCRYPTED room: can't read history -> reply gets "stuck typing"
#     ("Local cache doesn't contain all necessary data")
#   - in a PLAIN room: its own send is rejected ("Event is not authorized")
#
# THE WORKAROUND (what this does): restart baibot. On the fresh /sync, any room
# it has ALREADY joined comes down with complete state (no join in progress to
# corrupt the response), so replies work again. This is the documented
# "restart" workaround from continuwuity's troubleshooting guide.
#
# WHEN TO USE:
#   - Hermes is in a room but never replies / gets stuck "typing"
#   - Adding Hermes to a NEW room: invite it, wait for "Hermes joined", THEN
#     run this, THEN send your first message (beats the join race)
#
# NOT A PERMANENT FIX. #779 is fixed by continuwuity commit eff454218c
# (2026-07-17), which is NOT in any tagged release as of v26.6.2 (2026-07-12) —
# the version this stack is pinned to. Once a release past that ships (Renovate
# will bump docker-compose.yml.j2), or if you move the image to the `main` tag,
# the bug is gone and this script is no longer needed. See README.md.
#
# Usage:
#   ./resync-baibot.sh          # restart baibot, report status
#   ./resync-baibot.sh --logs   # ...and show recent baibot logs for diagnosis
set -euo pipefail
NEO=${NEO:-ansible@192.168.1.3}

echo "Restarting baibot to force a fresh room-state sync (continuwuity #779)..."
ssh "$NEO" 'sudo docker restart baibot >/dev/null'
sleep 12
echo -n "baibot is now: "
ssh "$NEO" 'sudo docker inspect baibot --format "{{.State.Status}} (restarts={{.RestartCount}})"'
echo
echo "Send a message in the room where Hermes is a member. If it STILL doesn't"
echo "reply, that room likely hit the join race after this restart — run this"
echo "once more, then send again. If repeated runs never help, the fix is a"
echo "continuwuity version bump (see README.md), not this workaround."

if [ "${1:-}" = "--logs" ]; then
  echo
  echo "--- recent baibot logs ---"
  ssh "$NEO" 'sudo docker logs baibot --since 40s 2>&1' \
    | sed 's/\x1b\[[0-9;]*m//g' | grep -ivE 'Syncing\.\.|^[[:space:]]*$' | tail -15
fi
