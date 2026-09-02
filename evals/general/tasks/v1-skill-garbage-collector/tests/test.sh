#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/collected.json ]; then
  if python3 - <<'PYEOF'
import json
heap = json.load(open('/app/heap.json'))
roots = heap['roots']; objects = heap['objects']
marked = set(roots)
stack = list(roots)
while stack:
    cur = stack.pop()
    for nxt in objects.get(cur, []):
        if nxt not in marked:
            marked.add(nxt)
            stack.append(nxt)
exp = sorted(o for o in objects if o not in marked)
got = json.load(open('/app/collected.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt