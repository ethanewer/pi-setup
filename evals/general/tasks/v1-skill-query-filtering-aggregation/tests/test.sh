#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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