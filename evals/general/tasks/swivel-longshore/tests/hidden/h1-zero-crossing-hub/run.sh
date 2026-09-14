#!/bin/bash
# Hidden case h1 (swivel-longshore): a 6-node graph with group C={0,2,3}
# where NO shortest path between two non-group nodes passes through the
# group's interior, so the mathematically correct group betweenness is 0.
# The buggy code (plain all-pairs counts in the crossing-rate denominator)
# returns 1/9 here. The expectation is computed by an independent
# definition-based reference (layered-BFS path-count DP), not by the code
# under test.
set -u
python3 -s - <<'PY'
import sys
from collections import deque
import itertools

sys.path.insert(0, "/app/src")

import networkx as nx

EDGES = [
    (0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
    (1, 2), (1, 3), (1, 4), (1, 5),
    (2, 4), (2, 5), (3, 4), (4, 5),
]
N = 6
C = [2, 3, 0]


def ref_gbc(edges, n, group):
    """Independent reference: the documented definition of group betweenness
    centrality, summed over unordered non-group pairs."""
    group = set(group)
    adj = [[] for _ in range(n)]
    for a, b in edges:
        adj[a].append(b)
        adj[b].append(a)
    total = 0.0
    nonC = [x for x in range(n) if x not in group]
    for s, t in itertools.combinations(nonC, 2):
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
        # shortest s->t paths that never step onto a group node (so their
        # interior avoids the group entirely)
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
print(f"h1 GBC={got!r} expected={want!r}")
if abs(got - want) > 1e-9:
    sys.exit(1)
sys.exit(0)
PY