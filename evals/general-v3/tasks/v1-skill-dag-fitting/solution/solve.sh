#!/bin/bash
set -euo pipefail
cat > /app/dag.py <<'PY'
import heapq, json

edges = []
nodes = set()
with open('/app/edges.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        u, v = map(int, line.split())
        edges.append((u, v))
        nodes.add(u); nodes.add(v)

adj = {n: [] for n in nodes}
indeg = {n: 0 for n in nodes}
for u, v in edges:
    adj[u].append(v)
    indeg[v] += 1

pq = [n for n in nodes if indeg[n] == 0]
heapq.heapify(pq)
order = []
while pq:
    u = heapq.heappop(pq)
    order.append(u)
    for v in adj[u]:
        indeg[v] -= 1
        if indeg[v] == 0:
            heapq.heappush(pq, v)

dist = {n: 0 for n in nodes}
for u in order:
    for v in adj[u]:
        if dist[u] + 1 > dist[v]:
            dist[v] = dist[u] + 1

with open('/app/dag_result.json', 'w') as f:
    json.dump({"longest_path_length": max(dist.values()), "order": order}, f)
PY
python3 /app/dag.py