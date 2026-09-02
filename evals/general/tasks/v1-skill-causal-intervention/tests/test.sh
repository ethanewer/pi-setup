#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/graph.json ]; then
  if python3 - <<'PYEOF'
import json
g = json.load(open('/app/graph.json'))
nodes = g['nodes']
edges = g['edges']
target = g['target']

def reaches(n, target):
    seen = set()
    stack = [n]
    while stack:
        cur = stack.pop()
        if cur == target:
            return True
        if cur in seen:
            continue
        seen.add(cur)
        for nxt in edges.get(cur, []):
            stack.append(nxt)
    return False

expected = [n for n in nodes if n != target and not reaches(n, target)]
got = json.load(open('/app/cannot_reach.json'))
assert isinstance(got, dict) and 'cannot_reach_target' in got
assert got['cannot_reach_target'] == expected, (got['cannot_reach_target'], expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt