#!/usr/bin/env python3
"""Hidden case for chainplate-bollard: MultiGraph input driven by direct
next().

The upstream regression test uses a plain Graph. A MultiGraph reaches the
same lazy-init code path through different edge iteration (keys=True), so
a correct fix must also cover multigraphs when next() is called directly.
The count is checked against Kirchhoff's theorem for the underlying
3-cycle. On the unfixed parent tree the first next() raises AttributeError
and the script exits non-zero.
"""
import networkx as nx

MG = nx.MultiGraph(nx.cycle_graph(3))  # 3 nodes, 3 edges, 3 spanning trees
it = nx.SpanningTreeIterator(MG)  # no iter() call anywhere below

t = next(it)  # must not raise AttributeError
assert isinstance(t, nx.Graph), type(t)
assert nx.is_tree(t)
assert set(t.nodes) == {0, 1, 2}
assert t.number_of_edges() == 2

# exhaust the rest with direct next(); a 3-cycle has exactly 3 spanning trees
count = 1
try:
    while True:
        tt = next(it)
        assert nx.is_tree(tt)
        assert set(tt.nodes) == {0, 1, 2}
        assert tt.number_of_edges() == 2
        count += 1
except StopIteration:
    pass
assert count == 3, f"expected 3 spanning trees for the 3-cycle, got {count}"
print("OK multigraph: direct next() works on a MultiGraph, 3 trees found")