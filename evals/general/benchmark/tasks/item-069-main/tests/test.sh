#!/bin/bash

mkdir -p /logs/verifier

reward=0

if [ -f /app/recovered/recovered.json ]; then
python3 - <<'PY'
import json, sys

try:
    d = json.load(open('/app/recovered/recovered.json'))
    rec = d['recovered']
    cnt = d['count']
except Exception:
    sys.exit(1)

# must be a list of ints, ascending, unique
if not isinstance(rec, list):
    sys.exit(1)
if cnt != len(rec):
    sys.exit(1)
if any(not isinstance(x, int) for x in rec):
    sys.exit(1)
if rec != sorted(rec) or len(set(rec)) != len(rec):
    sys.exit(1)

# gold: the exact set of rows physically present in the truncated file
# (rows on the surviving leaf page, ids 1..140; ids 141..200 lived on the
# truncated page 4 and must NOT be reported)
GOLD = set(range(1, 141))

if set(rec) != GOLD:
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt