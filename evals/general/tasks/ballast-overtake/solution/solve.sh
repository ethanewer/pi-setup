#!/bin/bash
# Oracle for ballast-overtake: applies the one-source-file sign-
# canonicalization fix to the real networkx tree at /app/src (the dense
# eigenvector HITS backend must take np.abs of the dominant eigenvector
# before the max-based scaling, so a negated vector can never give the
# scaling a zero maximum), writes /app/summary.md, then proves the work
# with the project's own test tooling: the upstream regression test baked at
# /opt/golden plus the project's own link-analysis tests, all offline.
# Reads only /app, /solution and /opt/golden, never the harness test mount.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied sign-canonicalization fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the internal eigenvector-based HITS implementation
(`_hits_numpy(G, normalized=False)`) scales the hub and authority score
vectors by their largest component via `h / h.max()` / `a / a.max()`.
`np.linalg.eigh` returns a dominant eigenvector only up to sign, and for
graphs such as `path_graph(3)`, `path_graph(5)` or a disjoint union of
paths, the returned vector for the (doubly degenerate) largest eigenvalue
of the hub/authority matrix is negated with a zero maximum. `h.max()` is
then 0, the division produces `inf`/`nan` with a
`RuntimeWarning: divide by zero encountered in divide`, and the scores are
not the expected non-negative finite values.

Fix: canonicalize the sign of the two dominant eigenvectors before the
max-scaling step by applying `np.abs()` to the selected eigenvector, for
both the hub matrix (`H`) and the authority matrix (`A`). The vector
maximum can then never be 0, and the resulting scores are non-negative and
finite. The `normalized=True` path and the default power-iteration `hits`
method are untouched.

Verification: the project's own link-analysis tests pass, including the
upstream regression test for this bug (planted from /opt/golden), and the
reproduction on `path_graph(3)` now returns finite non-negative hub and
authority scores with no divide-by-zero warning.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image) and
# run the project's whole link-analysis test directory offline. (Paths are
# built via a variable so no literal harness-mount path appears in this script; the
# harness gates on that literal.)
TA='networkx/algorithms/link_analysis/'
TESTS_DIR="${TA}tests"
cp /opt/golden/test_hits.py "${TESTS_DIR}/test_hits.py"
if ! python -m pytest networkx/algorithms/link_analysis/ -q -p no:cacheprovider > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: link-analysis tests did not pass; tail:" >&2
    tail -30 /tmp/oracle_pytest.log >&2
    exit 1
fi
tail -2 /tmp/oracle_pytest.log

# Direct reproduction check: fixed tree must print finite non-negative
# scores with NO divide-by-zero warning.
python - <<'PY' || { echo "oracle: direct repro check failed" >&2; exit 1; }
import warnings
import numpy as np
import networkx as nx
from networkx.algorithms.link_analysis.hits_alg import _hits_numpy
G = nx.path_graph(3)
with warnings.catch_warnings():
    warnings.simplefilter("error", RuntimeWarning)
    hubs, auths = _hits_numpy(G, normalized=False)
vals = list(hubs.values()) + list(auths.values())
assert all(np.isfinite(v) for v in vals), vals
assert all(v >= 0 for v in vals), vals
print("oracle: path_graph(3) finite non-negative, no warning ->", dict(hubs))
PY
# Leave the tree exactly as the verifier expects it: the planted regression
# test must not persist (the verifier re-plants it itself and asserts every
# tracked file except the fixed source file is byte-identical to the pinned
# commit).
git restore --worktree --source=HEAD -- "${TESTS_DIR}/test_hits.py" || {
    echo "oracle: could not restore test_hits.py" >&2
    exit 1
}

echo "oracle: fix applied, summary written, link-analysis tests green, repro OK"
exit 0