#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/output.json ]; then
  if python3 - <<'PYEOF'
import csv, json

rows = []
with open('/app/data.csv', newline='') as f:
    for d in csv.DictReader(f):
        rows.append({"id": d['id'], "name": d['name'],
                     "role": d['role'], "years": int(d['years'])})
expected = json.dumps(rows, sort_keys=True)
got_norm = json.dumps(json.loads(open('/app/output.json').read()), sort_keys=True)
if got_norm != expected:
    raise SystemExit('mismatch')
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt