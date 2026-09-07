#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/stats.json ]; then
  if python3 - <<'PYEOF'
import csv, json, math
rows = list(csv.DictReader(open('/app/sales.csv', newline='')))
amounts = [int(r['amount']) for r in rows]
count = len(amounts)
total = sum(amounts)
avg = total / count
got = json.load(open('/app/stats.json'))
assert got['count'] == count, got
assert got['total'] == total, got
assert abs(float(got['avg']) - avg) < 1e-9, got
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt