#!/bin/bash
set -euo pipefail

cat > /app/gc.py <<'EOF'
import json

heap = json.load(open('/app/heap.json'))
roots = heap['roots']
objects = heap['objects']

marked = set(roots)
stack = list(roots)
while stack:
    cur = stack.pop()
    for nxt in objects.get(cur, []):
        if nxt not in marked:
            marked.add(nxt)
            stack.append(nxt)

collected = sorted(o for o in objects if o not in marked)
with open('/app/collected.json', 'w') as f:
    json.dump(collected, f)
EOF
python3 /app/gc.py