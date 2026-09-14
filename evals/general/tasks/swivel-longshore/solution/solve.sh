#!/bin/bash
# Oracle for swivel-longshore: applies the one-line upstream fix to the real
# networkx/networkx tree at /app/src (the dvxy crossing-rate term must use
# the group-aware path counts sigma_m, not the all-pairs counts sigma),
# writes /app/repro.py and /app/summary.md, then proves the work: the
# reproduction passes against the repaired tree and fails against the baked
# pristine pre-fix tree (per-build random path from /opt/prefix-path,
# root-only); the tree's own group
# centrality tests stay green; the canonical defect graph (upstream
# regression input) now yields exactly 0.0. Reads only /app, /solution and
# /opt; never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

PRE=$(cat /opt/prefix-path 2>/dev/null || true)
if [ -z "$PRE" ] || [ ! -r "$PRE/networkx/algorithms/centrality/group.py" ]; then
    echo "oracle: cannot resolve the pre-fix tree ("/opt/prefix-path")" >&2
    exit 1
fi

if [ "$(git rev-parse HEAD)" != "a7d049b4992a1f7e9bd376ce7378d3825d0cfa0e" ]; then
    echo "oracle: unexpected HEAD" >&2
    exit 1
fi
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the sigma -> sigma_m fix"

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for the spurious group-betweenness contribution.

Demonstrates the defect: group_betweenness_centrality returns a non-zero
value for a group even though NO shortest path between any two non-group
nodes has an interior node in the group, where the correct value is 0.

Honours NX_PACKAGE_ROOT (prepended to sys.path before importing networkx;
when unset, the installed package is used). Prints exactly one line
GBC=<value> and exits 0 iff the value is the mathematically correct one.
Works regardless of the current working directory.
"""
import os
import sys

_root = os.environ.get("NX_PACKAGE_ROOT")
if _root:
    sys.path.insert(0, _root)

import networkx as nx

# The group C = {0, 1, 2}. Non-group nodes are 3, 4, 5: 3-4 and 4-5 are
# direct edges and the only other shortest path (3-4-5) has interior {4}
# which is NOT in C. So no pair of non-group nodes has a shortest path with
# an interior group node: the group betweenness is exactly 0. The value
# must not be normalized (normalized=False uses the raw sum of path
# fractions), exactly as the comparison below does.
G = nx.Graph(
    [(0, 1), (0, 2), (0, 3), (0, 4), (1, 3), (2, 3), (3, 4), (4, 5)]
)
C = [0, 1, 2]
gbc = nx.group_betweenness_centrality(G, C, normalized=False)
print(f"GBC={gbc}")
correct = 0.0
if abs(gbc - correct) <= 1e-9:
    sys.exit(0)
sys.exit(1)
PY
chmod +x /app/repro.py
echo "oracle: wrote /app/repro.py"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Root cause

File: `networkx/algorithms/centrality/group.py`, function
`group_betweenness_centrality`.

Group betweenness centrality is the sum, over all pairs (s, t) of nodes
outside the group C, of the fraction of shortest s-t paths that pass
through some vertex of C. The algorithm walks the group nodes v in turn and
maintains two path-count tables: `sigma` (all-pairs shortest-path counts
over the whole graph) and `sigma_m` (the group-aware counts, which know
which nodes lie in C).

The crossing-rate term `dvxy` — the fraction of shortest v-y paths that
pass through x (both inside the group) and therefore through the group —
must be built entirely from the group-aware counts:

    dvxy = sigma_m[v][x] * sigma_m[x][y] / sigma_m[v][y]

The shipped code instead used the all-pairs table for the second and third
factors:

    dvxy = sigma_m[v][x] * sigma[x][y] / sigma[v][y]      # BUG

so the denominator was the total number of shortest v-y paths over the
whole graph rather than the number that stay within the group-aware
structure. When `sigma[v][y] > sigma_m[v][y]`, the phantom extra paths
injected a spurious positive contribution into the sum. That is exactly why
the function reported 0.125 for the group {0, 1, 2} on a 6-node graph in
which no shortest path between two non-group nodes has an interior group
node (correct value 0). The same spurious term is why singleton groups can
disagree with ordinary betweenness centrality.

## Change

One expression on one line in `group_betweenness_centrality`:

    - dvxy = sigma_m[v][x] * sigma[x][y] / sigma[v][y]
    + dvxy = sigma_m[v][x] * sigma_m[x][y] / sigma_m[v][y]

(the zero-denominator guard already present above the term already skips
the degenerate sigma_m cases correctly.)

## Verification

- `/app/repro.py` (this task's reproduction): against the pristine pre-fix
  tree (at the verifier-disclosed root-only path) it prints GBC=0.125 and
  exits 1; against the repaired tree it prints GBC=0.0 and exits 0.
- Direct check on the upstream regression input: 0.0 for the group
  {0,1,2} on the 8-edge graph.
- Singleton invariant: `group_betweenness_centrality(G, [[v] for v in G])`
  equals `betweenness_centrality(G, normalized=False)` per node on the test
  graphs it is checked against.
- Project suite: `python3 -m pytest` on the project's group-centrality test
  module, run from the tree's centrality directory — all green on the
  repaired tree.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the two trees.
if ! python3 -s /app/repro.py > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.py failed on the repaired tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if NX_PACKAGE_ROOT=$PRE python3 -s /app/repro.py \
        > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.py PASSED against the pre-fix tree (expected failure)" >&2
    cat /tmp/oracle_repro_prefix.out >&2
    exit 1
fi
grep -q "GBC=0.125" /tmp/oracle_repro_prefix.out || {
    echo "oracle: pre-fix run did not show the buggy 0.125 value" >&2
    cat /tmp/oracle_repro_prefix.out >&2
    exit 1
}
grep -q "GBC=0.0" /tmp/oracle_repro_fixed.out || {
    echo "oracle: fixed run did not print GBC=0.0" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
}
echo "oracle: repro fails on pre-fix tree (GBC=0.125), passes on repaired tree (GBC=0.0)"

# Sanity: the canonical defect graph must now give 0.0, singletons must
# agree with plain betweenness, and the project's own group tests must pass.
python3 -s - <<'PY'
import networkx as nx
G = nx.Graph([(0, 1), (0, 2), (0, 3), (0, 4), (1, 3), (2, 3), (3, 4), (4, 5)])
assert nx.group_betweenness_centrality(G, [0, 1, 2], normalized=False) == 0.0
H = nx.path_graph(5)
H.remove_edge(0, 1)
bc = nx.betweenness_centrality(H, normalized=False)
gbc = nx.group_betweenness_centrality(H, [[n] for n in H], normalized=False)
assert list(bc.values()) == gbc, (bc, gbc)
print("oracle: canonical defect graph gives 0.0; singleton groups agree with plain betweenness")
PY
# Project suite: run the tree's own group-centrality test module from the
# centrality directory (relative path keeps the module name).
if ! ( cd /app/src/networkx/algorithms/centrality \
       && python3 -s -m pytest tests/test_group.py -p no:cacheprovider -q \
            > /tmp/oracle_group_tests.log 2>&1 ); then
    echo "oracle: project group tests failed; tail:" >&2
    tail -20 /tmp/oracle_group_tests.log >&2
    exit 1
fi
grep -qE "[0-9]+ passed" /tmp/oracle_group_tests.log || {
    echo "oracle: group tests did not pass" >&2
    tail -10 /tmp/oracle_group_tests.log >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, repro OK both directions, group tests green"
exit 0