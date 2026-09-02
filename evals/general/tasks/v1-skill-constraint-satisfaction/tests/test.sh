#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/assignment.json ]; then
  if python3 - <<'PYEOF'
import json

prob = json.load(open('/app/graph.json'))
colors = set(prob['colors'])
regions = set(prob['regions'])
adjacency = prob['adjacency']

assign = json.load(open('/app/assignment.json'))
if set(assign.keys()) != regions:
    raise SystemExit("regions mismatch")
for c in assign.values():
    if c not in colors:
        raise SystemExit(c)
for a, b in adjacency:
    if assign[a] == assign[b]:
        raise SystemExit((a, b))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt