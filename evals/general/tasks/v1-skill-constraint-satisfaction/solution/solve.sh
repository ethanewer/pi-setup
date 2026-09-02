#!/bin/bash
set -euo pipefail

cat > /app/color.py <<'PYEOF'
import json, itertools

with open('/app/graph.json') as f:
    prob = json.load(f)

colors = prob['colors']
regions = prob['regions']
adjacency = prob['adjacency']

for combo in itertools.product(colors, repeat=len(regions)):
    assign = dict(zip(regions, combo))
    ok = True
    for a, b in adjacency:
        if assign[a] == assign[b]:
            ok = False
            break
    if ok:
        with open('/app/assignment.json', 'w') as f:
            json.dump(assign, f)
        break
else:
    raise SystemExit("no valid coloring found")
PYEOF

python3 /app/color.py