#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/report.json ]; then
  if python3 - <<'PY'
import json, collections
tot=collections.defaultdict(int)
with open('/app/transactions.tsv') as f:
    lines=f.read().splitlines()
    for line in lines[1:]:
        if not line.strip():
            continue
        p=line.split('\t')
        if p[3]=='active':
            tot[p[1]]+=int(p[2])
expected={k:tot[k] for k in sorted(tot)}
got=json.load(open('/app/report.json'))
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt