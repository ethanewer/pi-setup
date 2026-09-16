#!/usr/bin/env python3
"""Hidden case for ballast-overtake: disjoint union of path_graph(5) and a
single edge (path_graph(2)).

A disconnected graph reaching the same broken scaling path as the upstream
regression test (which uses a connected 3-path). On the unfixed parent tree
the scores are inf/nan with a divide-by-zero RuntimeWarning; a correct fix
must return finite non-negative scores matching the sign-canonicalized
dominant-eigenvector normalization with no warning.
"""
import warnings

import numpy as np
import networkx as nx
from networkx.algorithms.link_analysis.hits_alg import _hits_numpy

CASE = "path5-path2"
G = nx.disjoint_union(nx.path_graph(5), nx.path_graph(2))

with warnings.catch_warnings():
    warnings.simplefilter("error", RuntimeWarning)  # divide-by-zero must be gone
    hubs, auths = _hits_numpy(G, normalized=False)

values = list(hubs.values()) + list(auths.values())
assert all(np.isfinite(v) for v in values), f"{CASE}: non-finite scores: {values}"
assert all(v >= 0 for v in values), f"{CASE}: negative scores: {values}"

adj = nx.to_numpy_array(G)
e, ev = np.linalg.eigh(adj @ adj.T)
hub_ref = np.abs(ev[:, np.argmax(e)])
hub_ref /= hub_ref.max()
e2, ev2 = np.linalg.eigh(adj.T @ adj)
auth_ref = np.abs(ev2[:, np.argmax(e2)])
auth_ref /= auth_ref.max()

for i, n in enumerate(list(G)):
    assert abs(hubs[n] - hub_ref[i]) <= 1e-10, f"{CASE}: hub[{n}]={hubs[n]} != ref {hub_ref[i]}"
    assert abs(auths[n] - auth_ref[i]) <= 1e-10, f"{CASE}: auth[{n}]={auths[n]} != ref {auth_ref[i]}"

print(f"OK {CASE} finite non-negative, no warning, matches canonical eigenvector normalization")