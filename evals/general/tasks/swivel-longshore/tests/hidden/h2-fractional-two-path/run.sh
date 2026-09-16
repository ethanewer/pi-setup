#!/bin/bash
# Hidden case h2 (swivel-longshore): a 7-node graph with group C={0,2,4}
# where the correct group betweenness is a fractional value 1.5; the buggy
# code returns 1.625. The expectation is computed by an independent
# definition-based reference, and additionally the single-node-group
# invariant (group betweenness of {v} equals ordinary betweenness of v) is
# checked on a second graph the upstream tests do not use.
set -u
python3 -s - <<'PY'
import sys
from collections import deque
import itertools

sys.path.insert(0, "/app/src")

import networkx as nx

EDGES = [
    (0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
    (1, 3), (1, 4), (2, 5), (2, 6), (3, 6), (4, 5), (5, 6),
]
N = 7
C = [0, 2, 4]


def ref_gbc(edges, n, group):
    group = set(group)
    adj = [[] for _ in range(n)]
    for a, b in edges:
        adj[a].append(b)
        adj[b].append(a)
    total = 0.0
    for s, t in itertools.combinations([x for x in range(n) if x not in group], 2):
        dist = {s: 0}
        q = deque([s])
        while q:
            u = q.popleft()
            for v in adj[u]:
                if v not in dist:
                    dist[v] = dist[u] + 1
                    q.append(v)
        if t not in dist:
            continue
        sig = {s: 1.0}
        for u in sorted(dist, key=dist.get):
            for v in adj[u]:
                if dist.get(v) == dist[u] + 1:
                    sig[v] = sig.get(v, 0.0) + sig[u]
        avoid = {s: 1.0}
        for u in sorted(dist, key=dist.get):
            for v in adj[u]:
                if dist.get(v) == dist[u] + 1 and v not in group:
                    avoid[v] = avoid.get(v, 0.0) + avoid.get(u, 0.0)
        total += (sig[t] - avoid.get(t, 0.0)) / sig[t]
    return total


G = nx.Graph(EDGES)
assert nx.is_connected(G)
got = nx.group_betweenness_centrality(G, C, normalized=False)
want = ref_gbc(EDGES, N, C)
print(f"h2 GBC={got!r} expected={want!r}")
if abs(got - want) > 1e-9:
    sys.exit(1)

# Singleton-group invariant on a graph the upstream tests do not use.
H = nx.path_graph(7)
bc = nx.betweenness_centrality(H, normalized=False)
gbc_all = nx.group_betweenness_centrality(H, [[v] for v in H], normalized=False)
if len(gbc_all) != len(H) or any(abs(a - b) > 1e-9 for a, b in zip(bc.values(), gbc_all)):
    print(f"h2 singleton invariant violated: {list(bc.values())} vs {gbc_all}")
    sys.exit(1)
sys.exit(0)
PY