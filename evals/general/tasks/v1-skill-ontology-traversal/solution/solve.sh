#!/bin/bash
# Oracle solution for skill-ontology-traversal.
set -euo pipefail

cat > /app/traverse.py <<'PYEOF'
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

with open('/app/ancestors.txt', 'w') as f:
    for name in sorted(names[i] for i in seen):
        f.write(name + '\n')
PYEOF

python3 /app/traverse.py