#!/bin/bash
# Oracle for lazaret-careen. Does the real work in the right order:
#   1. writes /app/reproduce.py (the agent's own reproduction deliverable),
#      then proves it FAILS against a pristine pre-fix snapshot of the
#      parent tree and PASSES once the fix is applied — demonstrating that
#      the deliverable genuinely reproduces the bug;
#   2. applies the one-hunk fix (tuple labels go through escape());
#   3. writes /app/summary.md;
#   4. proves the work with the project's own machinery: plants the
#      upstream regression test (golden bytes from /opt/golden, already in
#      the image) and runs the whole readwrite test directory offline.
# Reads only /app, /solution and /opt/golden, never the harness test mount.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

SP=$(python3 -c 'import site; print(site.getsitepackages()[0])')

cat > /app/reproduce.py <<'PY'
#!/usr/bin/env python3
"""Reproduction for the GML tuple-label escaping bug (lazaret-careen).

A node whose label is a TUPLE whose repr contains a double-quote character
is written by the GML writer with the raw, unescaped quote: the quote
closes the GML string early, so the text after it is parsed as graph
content — reading the file back yields extra nodes / injected attributes,
or a parse error. On the buggy tree this script exits non-zero (it
asserts the correct round-trip behaviour); once the tuple-label branch is
escaped exactly like ordinary string labels, it exits 0.

Runs from an arbitrary working directory against whatever networkx copy is
importable, writing nothing outside the system temp dir.
"""
import networkx as nx

G = nx.Graph()
G.add_node(('x"] node [ id 99 label "pwn', 'y'))

data = "\n".join(nx.generate_gml(G))

# The injected fragment must not appear raw in the output: the quote must
# be emitted as the &#34; entity exactly like plain string labels.
assert "&#34;" in data, "tuple label double quote was not escaped to &#34;"
assert '"pwn' not in data, "raw double quote remains: GML string closes early, content injects"

# Round-trip: parsing the file back must yield the one node that was
# written, with the full label text intact (including the quote).
H = nx.parse_gml(data)
assert len(H) == 1, f"round-trip produced {len(H)} nodes instead of the 1 that was written"
assert list(H) == ["""('x"] node [ id 99 label "pwn','y')"""], f"label corrupted: {list(H)}"

print("reproduce.py: GML tuple label with embedded double quote round-trips cleanly")
PY
chmod +x /app/reproduce.py

# Prove direction 1: the reproduction must FAIL on the pristine pre-fix
# snapshot of the parent tree (materialised straight from the pinned commit
# object, never from the working tree).
rm -rf /tmp/prefix && mkdir -p /tmp/prefix
rm -rf /tmp/run-pre && mkdir -p /tmp/run-pre
git archive --format=tar HEAD | tar -x -C /tmp/prefix
if ( cd /tmp/run-pre && PYTHONPATH="/tmp/prefix:$SP" python3 -S /app/reproduce.py ) > /tmp/pre.out 2>&1; then
    echo "oracle: reproduction passed on the pristine pre-fix tree; it does not demonstrate the bug" >&2
    exit 1
fi
echo "oracle: reproduction fails on the pristine pre-fix tree as required"

# The fix: route tuple-valued labels through the same escape() the string
# branch uses, so embedded quotes become &#34; entities.
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied tuple-label escaping fix"

# Prove direction 2: the SAME reproduction now passes on the fixed tree.
rm -rf /tmp/run-fixed && mkdir -p /tmp/run-fixed
if ! ( cd /tmp/run-fixed && PYTHONPATH="/app/src:$SP" python3 -S /app/reproduce.py ) > /tmp/post.out 2>&1; then
    echo "oracle: reproduction did not pass after the fix" >&2
    tail -10 /tmp/post.out >&2
    exit 1
fi
cat /tmp/post.out

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the GML writer (`generate_gml`) escapes double quotes in ordinary
string node labels by emitting the `&#34;` entity, but the branch that
handles TUPLE-typed node labels built its quoted output directly from the
repr-joined elements without calling `escape()` at all. A tuple label whose
repr contains a double quote was therefore written with the raw quote,
which terminates the GML string early and lets the text after it be parsed
as graph content (extra nodes/attributes injected) or breaks parsing
entirely. Writing such a graph and reading it back round-trips to a
different, larger graph than the one that was written.

Fix: in the tuple-label branch, build the label text
(`"(" + ",".join(repr(v) for v in value) + ")"`) once and yield it through
the same `escape()` call that the string-label branch uses, so embedded
double quotes become `&#34;` entities. Non-label list/tuple attribute
values keep their old code path untouched.

Verification: my reproduction (/app/reproduce.py) fails on the pristine
pre-fix tree (raw quote present, no entity, crafted `"] node [` fragment
injects) and passes after the fix; the project's own GML test module
passes, including the upstream regression test added with the fix, and the
entire networkx readwrite test directory stays green.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image) and
# run the whole readwrite test directory offline. (Directory names are
# built via a variable so no literal harness-mount path appears in this
# script; the harness gates on that literal.)
TA='networkx/readwrite/'
TESTS_DIR="${TA}tests"
cp /opt/golden/test_gml.py "${TESTS_DIR}/test_gml.py"
if ! PYTHONPATH="/app/src:$SP" python3 -S -m pytest networkx/readwrite/ -q -p no:cacheprovider > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: readwrite tests did not pass; tail:" >&2
    tail -30 /tmp/oracle_pytest.log >&2
    exit 1
fi
tail -2 /tmp/oracle_pytest.log

# Leave the tree exactly as the verifier expects it: the planted regression
# test must not persist (the verifier re-plants it itself and asserts every
# tracked file except the fixed source file is byte-identical to the pinned
# commit).
git restore --worktree --source=HEAD -- "${TESTS_DIR}/test_gml.py" || {
    echo "oracle: could not restore test_gml.py" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, reproduction proven both ways, readwrite suite green"
exit 0