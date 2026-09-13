#!/usr/bin/env python3
"""Hidden case for chainplate-bollard: direct next() exhaustion on
cycle_graph(4).

The upstream regression test calls next() exactly once on an unweighted
3-cycle. This case drives the same lazy-init code path with a different
graph (a 4-cycle), exhausts the whole sequence with repeated direct next()
calls (never touching iter()/for), and checks the count against
Kirchhoff's theorem: a cycle on n nodes has exactly n spanning trees. On
the unfixed parent tree the first next() raises AttributeError and the
script exits non-zero.
"""
import networkx as nx

G = nx.cycle_graph(4)  # 4 nodes, 4 edges, 4 spanning trees
it = nx.SpanningTreeIterator(G)  # no iter() call anywhere below

trees = []
while True:
    try:
        t = next(it)
    except StopIteration:
        break
    assert isinstance(t, nx.Graph), type(t)
    assert nx.is_tree(t)
    assert set(t.nodes) == {0, 1, 2, 3}
    assert t.number_of_edges() == 3
    trees.append(t)

assert len(trees) == 4, f"cycle_graph(4) must yield exactly 4 spanning trees, got {len(trees)}"
# every spanning tree of a 4-cycle is a path graph on 4 nodes (degrees 1,1,2,2)
for t in trees:
    assert sorted(d for _, d in t.degree()) == [1, 1, 2, 2]
print("OK cycle4: 4 spanning trees via direct next(), all trees")