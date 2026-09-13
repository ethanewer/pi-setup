#!/bin/bash
# Oracle for chainplate-bollard: applies the spanning-tree-iterator fix to
# the real networkx tree at /app/src (make the internal partition priority
# queue initialise lazily from __next__ instead of only from __iter__, so a
# direct next() call works exactly as the protocol requires), writes
# /app/summary.md, then proves the work with the project's own test tooling:
# the upstream regression test baked at /opt/golden plus the project's own
# full mst test file, all offline. Reads only /app, /solution and /opt/golden.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied lazy-init fix to SpanningTreeIterator"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `nx.SpanningTreeIterator` defines both `__iter__` and `__next__`, so
the Python protocol allows building the object and calling `next()` on it
directly, with no prior `iter()` call. The one-time initialisation of the
internal partition priority queue, however, happened only inside `__iter__`.
Any `for` loop or `list(...)` call goes through `iter()` implicitly and
worked, which is why the project's pre-existing tests were all green — but a
direct `next(iterator)` raised
`AttributeError: ... no attribute 'partition_queue'` and the first spanning
tree could not be obtained.

Fix: initialise `self.partition_queue = None` in `__init__` and move the
one-time initialisation block (build the `PriorityQueue`, clear partition
data, compute the initial minimum/maximum spanning tree weight and seed the
queue) into `__next__`, guarded by `if self.partition_queue is None:`. The
initialisation now runs on first use whichever way the object is consumed,
the first `next()` returns the same tree the `for` loop would, and the
end-of-iteration behaviour (queue empty -> `StopIteration` and internal
cleanup) is unchanged.

Verification: the project's own mst test file passes, including the upstream
regression test for this bug (planted from /opt/golden), and direct `next()`
calls on `SpanningTreeIterator(nx.cycle_graph(3))` return a spanning tree;
the same direct-`next()` contract was sanity-checked on unweighted and
weighted graphs, `minimum=False`, exhaustion with `StopIteration`, and a
`MultiGraph` input.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image) and
# run the project's whole mst test file offline.
TA='networkx/algorithms/tree/'
cp /opt/golden/test_mst.py "${TA}tests/test_mst.py"
if ! python -m pytest "${TA}tests/test_mst.py" -q -p no:cacheprovider > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: mst tests did not pass with the regression test planted; tail:" >&2
    tail -30 /tmp/oracle_pytest.log >&2
    exit 1
fi
tail -2 /tmp/oracle_pytest.log

# Direct reproduction check: fixed tree must return a spanning tree from a
# direct next() call, with no AttributeError.
python - <<'PY'
import networkx as nx

t = next(nx.SpanningTreeIterator(nx.cycle_graph(3)))
assert isinstance(t, nx.Graph)
assert nx.is_tree(t)
assert t.number_of_edges() == 2
# protocol contract on the other entry path must be unchanged
count = 0
for _ in nx.SpanningTreeIterator(nx.cycle_graph(4)):
    count += 1
assert count == 4, count
print("oracle: direct next() returns a spanning tree; for-loop unchanged")
PY

# Leave the tree exactly as the verifier expects it: the planted regression
# test must not persist (the verifier re-plants it itself and asserts every
# tracked file except the fixed source file is byte-identical to the pinned
# commit).
git restore --worktree --source=HEAD -- "${TA}tests/test_mst.py" || {
    echo "oracle: could not restore test_mst.py" >&2
    exit 1
}

echo "oracle: fix applied, summary written, mst suite green, repro OK"
exit 0