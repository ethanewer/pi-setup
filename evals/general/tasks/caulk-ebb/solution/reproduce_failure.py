#!/usr/bin/env python3
"""Reproduction for the geometric_soft_configuration_graph mapping-form bug.

networkx.geometric_soft_configuration_graph is documented to accept the
hidden degree sequence as either a sequence of degrees or a mapping of
node-to-degree values.  With a mapping:

  * string node labels crash with a TypeError (the generator sums the
    mapping's KEYS as if they were numbers);
  * integer node labels do not crash, but the graph's edge structure and
    radial layout come out as if the NODE LABELS were the degrees.

This script exits nonzero while either failure mode is present, and exits 0
once the generator computes the mean hidden degree from the degree VALUES.
"""
import sys

import networkx as nx


def main() -> int:
    # 1. String node labels must produce a valid graph, not a TypeError.
    kappas = {f"n{i}": 2 for i in range(15)}
    G = nx.geometric_soft_configuration_graph(beta=2.5, kappas=kappas, seed=3)
    assert len(G) == 15
    assert max(deg for _, deg in G.degree) <= len(G)

    # 2. Integer node labels unrelated to the degrees must not change the
    #    meaning of the degrees: 40 nodes of mean degree 1 are sparse --
    #    roughly a dozen to a few dozen edges -- not empty and not complete.
    n = 40
    kappas = {1000 + i: 1 for i in range(n)}
    G = nx.geometric_soft_configuration_graph(beta=2.5, kappas=kappas, seed=42)
    assert G.number_of_edges() >= 5, "mean degree was read from the node ids, not the degree values"
    assert G.number_of_edges() < n * (n - 1) // 2

    print("ok: geometric_soft_configuration_graph handles kappas mappings correctly")
    return 0


if __name__ == "__main__":
    sys.exit(main())