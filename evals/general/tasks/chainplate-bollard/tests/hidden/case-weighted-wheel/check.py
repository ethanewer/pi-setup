#!/usr/bin/env python3
"""Hidden case for chainplate-bollard: weighted wheel graph, minimum and
maximum directions, driven by direct next() with no iter() call.

The upstream regression test uses an unweighted 3-cycle in the increasing
(minimum) direction only. This case exercises the same lazy-init path on a
wheel graph with distinct non-trivial weights, checks the first minimum
tree against an independently computed minimum spanning tree, checks the
maximum (minimum=False) branch the same way, and verifies that the whole
directly-next()ed minimum sequence is non-decreasing. On the unfixed parent
tree the first next() raises AttributeError and the script exits non-zero.
"""
import networkx as nx

# Wheel graph W6: 6 rim nodes + 1 hub. Assign distinct pseudo-random weights.
G = nx.wheel_graph(6)
for i, (u, v) in enumerate(sorted(G.edges())):
    G[u][v]["weight"] = (i * 7919) % 53 + 1
assert len({G[u][v]["weight"] for u, v in G.edges()}) == G.number_of_edges()


def wsum(t):
    return t.size(weight="weight")


# --- minimum direction via direct next() -------------------------------
it = nx.SpanningTreeIterator(G)
first = next(it)  # must not raise AttributeError
assert nx.is_tree(first)
assert first.number_of_edges() == G.number_of_nodes() - 1
mst = nx.minimum_spanning_tree(G)  # independent ordering of the same edge set
assert wsum(first) == wsum(mst), (wsum(first), wsum(mst))

weights = [wsum(first)]
try:
    while True:
        t = next(it)
        assert nx.is_tree(t)
        weights.append(wsum(t))
except StopIteration:
    pass
assert weights == sorted(weights), "minimum direction must be non-decreasing"

# --- maximum direction via direct next() -------------------------------
it = nx.SpanningTreeIterator(G, minimum=False)
m_first = next(it)  # must not raise AttributeError
max_t = nx.maximum_spanning_tree(G)
assert wsum(m_first) == wsum(max_t), (wsum(m_first), wsum(max_t))
print("OK weighted-wheel: min & max first trees match MST, weights non-decreasing")