#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/dag_result.json ]; then
  if python3 - <<'PYEOF'
import heapq, json
edges = []
nodes = set()
with open('/app/edges.txt') as f:
    for line in f:
        line=line.strip()
        if not line: continue
        u,v=map(int,line.split()); edges.append((u,v)); nodes.add(u); nodes.add(v)
adj={n:[] for n in nodes}; indeg={n:0 for n in nodes}
for u,v in edges:
    adj[u].append(v); indeg[v]+=1
pq=[n for n in nodes if indeg[n]==0]
heapq.heapify(pq)
order=[]
while pq:
    u=heapq.heappop(pq); order.append(u)
    for v in adj[u]:
        indeg[v]-=1
        if indeg[v]==0: heapq.heappush(pq,v)
dist={n:0 for n in nodes}
for u in order:
    for v in adj[u]:
        if dist[u]+1>dist[v]: dist[v]=dist[u]+1
expected={"longest_path_length": max(dist.values()), "order": order}
got = json.load(open('/app/dag_result.json'))
if json.dumps(got, sort_keys=True) != json.dumps(expected, sort_keys=True):
    raise SystemExit("mismatch")
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt