#!/bin/bash
set -euo pipefail

cat > /app/causal.py <<'EOF'
import json

g = json.load(open("/app/graph.json"))
nodes = g["nodes"]
edges = g["edges"]
target = g["target"]

def reaches(n):
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

cannot = [n for n in nodes if n != target and not reaches(n)]
json.dump({"cannot_reach_target": cannot}, open("/app/cannot_reach.json", "w"))
EOF

python3 /app/causal.py