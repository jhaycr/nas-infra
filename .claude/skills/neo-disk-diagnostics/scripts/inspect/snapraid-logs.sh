#!/usr/bin/env bash
# READ-ONLY: SnapRAID run timeline + error lines from Loki. Usage: snapraid-logs.sh [days]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DAYS="${1:-30}"
START="$(date -d "${DAYS} days ago" +%s)000000000"
END="$(date +%s)000000000"

loki() {
  curl -s -G "${LOKI_URL}/loki/api/v1/query_range" \
    --data-urlencode "query=$1" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${END}" \
    --data-urlencode "limit=${2:-100}" \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
lines=[]
for s in d.get("data",{}).get("result",[]):
    lines += [l for _,l in s.get("values",[])]
print("\n".join(sorted(lines)) if lines else "(no matching log lines)")'
}

section "Run outcomes (last ${DAYS}d): successes"
loki '{job="snapraid"} |= "Run finished successfully"'

section "Run outcomes (last ${DAYS}d): failures"
loki '{job="snapraid"} |~ "Run failed$"'

section "ERROR lines (last ${DAYS}d)"
loki '{job="snapraid"} |= "[ERROR ]"'

section "OUTERR lines (snapraid stderr — root causes usually here, last ${DAYS}d)"
loki '{job="snapraid"} |= "[OUTERR]"' 200
