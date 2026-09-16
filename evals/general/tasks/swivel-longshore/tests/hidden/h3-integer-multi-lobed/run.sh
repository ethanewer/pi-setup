#!/bin/bash
# Hidden case h3 (swivel-longshore): an 8-node two-lobed graph with group
# C={0,1,7} where the correct group betweenness is the integer 4.0; the
# buggy code returns 4.125. The expectation is independent (layered-BFS
# path-count DP reference). A second group on the same graph (singleton
# {3}) is checked with the list-of-groups calling convention.
set -u
python3 -s - <<'PY'
import sys
from collections import deque
import itertools

sys.path.insert(0, "/app/src")

import networkx as nx

EDGES = [
    (0, 1), (0, 2), (0, 5), (0, 6), (0, 7),
    (1, 4), (1, 6),
    (2, 7),
    (3, 5),
    (4, 5), (4, 6),
    (5, 6), (6, 7),
]
N = 8
C = [1, 0, 7]


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
print(f"h3 GBC={got!r} expected={want!r}")
if abs(got - want) > 1e-9:
    sys.exit(1)

# list-of-groups convention on the same graph: a singleton group {3} must
# match plain betweenness of node 3.
got_single = nx.group_betweenness_centrality(G, [[3]], normalized=False)[0]
want_single = nx.betweenness_centrality(G, normalized=False)[3]
if abs(got_single - want_single) > 1e-9:
    print(f"h3 singleton mismatch: {got_single} vs {want_single}")
    sys.exit(1)
sys.exit(0)
PY