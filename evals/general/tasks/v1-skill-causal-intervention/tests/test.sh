#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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