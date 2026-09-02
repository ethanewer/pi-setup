#!/bin/bash
# Dial the coordinator desk: identify yourself as the planner and receive the
# offsite phrase plus the per-person budget.
set -u
BASE="http://127.0.0.1:8701"

read -r -p "coordinator desk — your planner id? " pid
[ -n "${pid:-}" ] || { echo "coordinator: no planner id given."; exit 1; }

payload=$(python3 -c 'import json,sys
print(json.dumps({"planner_id": sys.argv[1]}))' "$pid") || exit 1

if ! resp=$(curl -s -m 15 -X POST "${BASE}/phrase" \
              -H 'Content-Type: application/json' -d "$payload"); then
  echo "coordinator: no answer (stack down? try /opt/offsite/up.sh)" >&2
  exit 1
fi

status=$(printf '%s' "$resp" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("status","error"))' 2>/dev/null || echo error)

if [ "$status" != "ok" ]; then
  echo "coordinator: sorry, you are not on the planner list."
  exit 1
fi

printf '%s' "$resp" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("coordinator: you are on the list. Give this phrase to each colleague:")
print("PHRASE=%s" % d["phrase"])
print("BUDGET=%s" % d["budget_eur"])
print("coordinator: collect availability, preferences and constraints from")
print("coordinator: Mara (:8702), Jonas (:8703) and Priya (:8704), then book")
print("coordinator: the winning plan at the booking desk.")'
