#!/bin/sh
# neo-diag — read-only docker/network diagnostics on neo for the Hermes
# agent. Client side only: the command menu and all validation are enforced
# SERVER-side on neo (forced-command key + root dispatcher, see the
# jhaycr-local.hermes_neo_diag role in nas-infra). Root-owned ro mount at
# /workspace/bin/neo-diag.
#
# Usage:
#   neo-diag logs <container> [tail]   # docker logs (default 200, max 2000)
#   neo-diag ps [name-filter]          # container names/status/image
#   neo-diag health <container>        # state/restarts/health/started
#   neo-diag listeners                 # listening TCP/UDP sockets (ss -ltnu)
# Filter output locally (grep/head) - the server returns raw text.
set -eu
exec ssh -i /etc/hermes/neo-diag.key \
  -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  hermes-diag@192.168.1.3 "$@"
