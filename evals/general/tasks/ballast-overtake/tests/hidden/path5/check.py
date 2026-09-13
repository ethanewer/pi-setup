#!/usr/bin/env python3
"""Hidden case for ballast-overtake: path_graph(5).

Exercises the same non-normalized eigenvector-scaling code path as the
upstream regression test but from a different graph. On the unfixed parent
tree, np.linalg.eigh returns the dominant eigenvector of the hub/authority
matrix negated with a zero maximum, so the max-scaling divides by zero
(RuntimeWarning) and the scores come out as inf/nan. The fixed
implementation must return finite, non-negative scores equal to the
sign-canonicalized (|.| max-normalized) dominant eigenvector, and must
never raise the divide-by-zero warning.
"""
import warnings

import numpy as np
import networkx as nx
from networkx.algorithms.link_analysis.hits_alg import _hits_numpy

CASE = "path5"
G = nx.path_graph(5)

with warnings.catch_warnings():
    warnings.simplefilter("error", RuntimeWarning)  # divide-by-zero must be gone
    hubs, auths = _hits_numpy(G, normalized=False)

values = list(hubs.values()) + list(auths.values())
assert all(np.isfinite(v) for v in values), f"{CASE}: non-finite scores: {values}"
assert all(v >= 0 for v in values), f"{CASE}: negative scores: {values}"

# Independent expectation: the sign-canonicalized dominant eigenvector of the
# hub/authority matrices, max-normalized. On a correct tree this matches the
# implementation exactly; a per-graph guard (e.g. clamping the zero maximum
# instead of canonicalizing the sign) produces negative or wrong scores here.
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