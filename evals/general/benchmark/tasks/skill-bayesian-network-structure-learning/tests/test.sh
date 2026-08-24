#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/edges.json ]; then
  if python3 - <<'PYEOF'
import json, math
names = ['A', 'B', 'C', 'D']
lines = [ln.strip() for ln in open('/app/data.csv') if ln.strip()]
data = [[int(x) for x in ln.split(',')] for ln in lines[1:]]
N = len(data)
maxv = [0, 0, 0, 0]
for r in data:
    for i in range(4):
        maxv[i] = max(maxv[i], r[i])
def marginal(idx):
    cnt = [0]*(maxv[idx]+1)
    for r in data:
        cnt[r[idx]] += 1
    return [c/float(N) for c in cnt]
margs = [marginal(i) for i in range(4)]
def mutual(u, v):
    I = 0.0
    for a in range(maxv[u]+1):
        for b in range(maxv[v]+1):
            n = sum(1 for r in data if r[u]==a and r[v]==b)
            pab = n/float(N)
            if pab > 0:
                I += pab*math.log2(pab/(margs[u][a]*margs[v][b]))
    return I
edges = []
for u in range(4):
    for v in range(u+1, 4):
        edges.append((names[min(u,v)], names[max(u,v)], mutual(u,v)))
edges_sorted = sorted(edges, key=lambda e: (-e[2], e[0], e[1]))
parent = {n:n for n in names}
def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[ra] = rb
        return True
    return False
tree = []
for u, v, w in edges_sorted:
    if union(u, v):
        tree.append([u, v])
    if len(tree) == 3:
        break
tree = sorted(tree, key=lambda e: (e[0], e[1]))
exp = tree
got = json.load(open('/app/edges.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt