#!/bin/bash
# Verifier for skill-ontology-traversal: recompute ancestors of "wolf", compare sorted names.
mkdir -p /logs/verifier
reward=0
if [ -f /app/ancestors.txt ]; then
  if python3 - <<'PYEOF'
import json

data = json.load(open('/app/ontology.json'))
names = {n['id']: n['name'] for n in data['nodes']}
parent = {e['child']: e['parent'] for e in data['edges']}

seen = set()
stack = ['wolf']
while stack:
    node = stack.pop()
    p = parent.get(node)
    if p is not None and p not in seen:
        seen.add(p)
        stack.append(p)

expected = sorted(names[i] for i in seen)
got = [line.rstrip('\n') for line in open('/app/ancestors.txt').read().splitlines() if line.strip() != '']
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt