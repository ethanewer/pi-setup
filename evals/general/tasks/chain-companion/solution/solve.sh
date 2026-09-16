#!/bin/bash
# Oracle for chain-companion: applies the one-source-file fix to the real
# nltk tree at /app/src (the fromstring token pattern must treat a
# backslash-escaped bracket as a literal token character), writes the
# agent-facing deliverable /app/repro.py, then proves the work end-to-end:
# the reproduction passes on the repaired tree, fails on a pristine pre-fix
# snapshot of the same package materialised from the pinned commit, the
# project's own regression test for this bug (baked at /opt/golden at image
# build time, sha256-pinned) passes 4/4, and the project's own existing
# tree test suite stays green. Reads only /app, /solution and /opt; never
# /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied single-file fix (escaped brackets are literal token chars)"

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Reproduction for the escaped-bracket parsing bug in nltk.tree.Tree.fromstring.

Run:  python3 /app/repro.py

A backslash-escaped '(' or ')' inside a labelled-bracket tree is a literal
character of the leaf or label that contains it.  The unpatched parser either
raises ValueError or silently treats the escaped bracket as structure, so the
input never round-trips.  This script exits 0 if and only if every sample
parses and `str(tree)` reproduces the source exactly.
"""
import sys

from nltk.tree import Tree

SAMPLES = (r"(S \))", r"(S \()", r"(EMOJI :\))")


def main() -> int:
    for source in SAMPLES:
        tree = Tree.fromstring(source)
        assert str(tree) == source, f"round-trip failed: {source!r} -> {str(tree)!r}"
        assert tree.leaves(), f"no leaf parsed from {source!r}"
    print("repro: escaped brackets parse and round-trip OK")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        print("repro: FAILED - escaped brackets do not parse/round-trip")
        raise
PY
chmod +x /app/repro.py
echo "oracle: wrote /app/repro.py"

# 1) the reproduction must pass against the repaired tree.
if ! python3 /app/repro.py > /tmp/oracle_repro.out 2>&1; then
    echo "oracle: repro failed on the repaired tree:" >&2
    tail -20 /tmp/oracle_repro.out >&2
    exit 1
fi

# 2) and must fail against a pristine pre-fix snapshot of the package
#    (materialised from the pinned HEAD; HEAD is the parent commit because
#    the oracle never commits).
rm -rf /tmp/prefix && mkdir -p /tmp/prefix
git archive HEAD nltk | tar -x -C /tmp/prefix || { echo "oracle: git archive failed" >&2; exit 1; }
if PYTHONPATH=/tmp/prefix python3 /app/repro.py > /tmp/oracle_pre.out 2>&1; then
    echo "oracle: repro PASSED against the pre-fix snapshot - not a genuine reproduction" >&2
    exit 1
fi
if grep -qi "importerror" /tmp/oracle_pre.out; then
    echo "oracle: repro failed on the pre-fix snapshot for import reasons:" >&2
    tail -20 /tmp/oracle_pre.out >&2
    exit 1
fi
echo "oracle: repro passes on fixed tree and fails on pre-fix snapshot"

# 3) the project's own regression test for this bug (from /opt/golden) and
#    the project's own existing tree test suite must both stay green.
if ! python3 -m pytest -q -p no:cacheprovider /opt/golden/test_tree_golden.py > /tmp/oracle_golden.out 2>&1; then
    echo "oracle: upstream regression test failed:" >&2
    tail -20 /tmp/oracle_golden.out >&2
    exit 1
fi
grep -q "4 passed" /tmp/oracle_golden.out || { echo "oracle: golden run did not report 4 passed" >&2; exit 1; }
echo "oracle: golden regression test 4/4"

if ! python3 -m pytest -q -p no:cacheprovider nltk/test/unit/test_treetransforms.py > /tmp/oracle_suite.out 2>&1; then
    echo "oracle: existing tree-transforms suite failed:" >&2
    tail -20 /tmp/oracle_suite.out >&2
    exit 1
fi
grep -q "5 passed" /tmp/oracle_suite.out || { echo "oracle: existing suite did not report 5 passed" >&2; exit 1; }
echo "oracle: existing tree-transforms suite 5/5"

echo "oracle: fix applied, /app/repro.py written, all checks green"
exit 0