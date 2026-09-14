#!/bin/bash
# Verifier for scantling-keel: proves the agent's fix in the real sympy/sympy
# tree at /app/src by (1) asserting the verifier's own trust anchors (sha256
# pins of the golden regression test, of the pre-fix solver module, and of
# the interpreter/toolchain), (2) asserting provenance (HEAD still the pinned
# parent commit; the upstream fix commit is not reachable from this clone),
# (3) diffing the whole working tree byte-for-byte against a pristine pre-fix
# checkout at /opt/prefix-sympy, allowing ONLY sympy/solvers/solveset.py to
# differ, (4) requiring /app/repro.py and /app/summary.md, (5) forcing the
# graded imports to resolve from /app/src, (6) running the agent's own
# reproduction against the repaired tree (must pass) and against the pristine
# pre-fix tree (must fail - proving the symptom is real and the reproduction
# targets it), (7) planting the project's own regression test for this bug
# (extracted from the fix commit at image build time into /opt/golden,
# sha256-pinned) and requiring it to FAIL against the pre-fix tree and PASS
# against the repaired tree, (8) running pre-existing nonlinsolve tests, and
# (9) running three authored hidden cases that reach the same solver code
# path from inputs the upstream regression test does not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=08e73e6bd6a5227e9382ea313715b363c06e88ad
FIX=d696c93fbb25f062f963b58a98c0ac1a07fec3fc
ALLOWED=sympy/solvers/solveset.py

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pristine pre-fix tree and the toolchain; an adversarial agent (e.g. a
#    root trial) could otherwise substitute /opt/prefix-sympy with a fixed
#    tree (so the pre-fix direction stops failing), tamper with the golden
#    test, or swap the interpreter for a stub. The pins recorded at image
#    build time detect any substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-solveset.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix solver or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0;
#    the fix direction must come from the agent's own work).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every tracked file on disk must be byte-identical to the pinned
#    commit except the single source file where the bug lives, and no stray
#    untracked file may be added. Implemented as a working-tree diff against
#    the pristine pre-fix checkout at /opt/prefix-sympy (build-time artifacts
#    __pycache__/*.egg-info/.pytest_cache/.hypothesis/.git are excluded).
ok=1
while IFS= read -r line; do
    allowed=0
    case "$line" in
        "$ALLOWED"*|*"$ALLOWED"*) allowed=1 ;;
    esac
    if [ "$allowed" = 0 ]; then
        echo "$line" >> "$LOG"
        ok=0
    fi
done < <(diff -rq -x .git -x __pycache__ -x '*.egg-info' -x .pytest_cache -x .hypothesis \
             /app/src /opt/prefix-sympy 2>&1 || true)
if [ "$ok" != "1" ]; then
    tail -50 "$LOG" >&2
    fail "working tree differs from the pinned commit outside $ALLOWED (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) import resolution: the graded runs must exercise the tree the agent
#    actually edited. Force /app/src onto the import path and confirm sympy
#    comes from there, so a planted site-packages wrapper or redirected
#    editable finder cannot stand in for the tree.
res=$(cd /app/src && SYMPY_SRC=/app/src python3 -c "import sympy; print(sympy.__file__)") \
    || fail "cannot import sympy from /app/src"
case "$res" in
    /app/src/*) : ;;
    *) fail "sympy imports from $res, not from /app/src" ;;
esac

# 5) the agent's reproduction, both directions. Against the repaired tree it
#    must pass (exit 0). Against the pristine pre-fix tree it must fail (any
#    exit 0 there means the reproduction is fake/hardcoded or the symptom is
#    not what is graded).
if ! ( cd /app/src && SYMPY_SRC=/app/src python3 /app/repro.py ) \
        > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; output:" >> "$LOG"
    head -20 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if ( cd /app/src && SYMPY_SRC=/opt/prefix-sympy python3 /app/repro.py ) \
        > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro passed against the PRE-FIX tree (expected failure); output:" >> "$LOG"
    head -20 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 6) golden regression test, both directions on a throwaway copy of the
#    pristine pre-fix tree (the copy is deleted afterwards; /opt/prefix-sympy
#    must stay byte-identical to the pinned commit for the diff in (2)).
rm -rf /tmp/prefix-golden
if ! cp -a /opt/prefix-sympy /tmp/prefix-golden; then
    fail "cannot copy the pre-fix reference tree"
fi
cp /opt/golden/test_solveset.py /tmp/prefix-golden/sympy/solvers/tests/test_solveset.py \
    || fail "cannot plant the golden test into the pre-fix copy"
chmod -R a+rwX /tmp/prefix-golden
( cd /tmp/prefix-golden && SYMPY_SRC=/tmp/prefix-golden python3 -m pytest \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_sign' \
        -p no:cacheprovider > /tmp/golden_prefix.out 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "golden test PASSED on the pre-fix tree (expected failure); output:" >> "$LOG"
    tail -8 /tmp/golden_prefix.out >> "$LOG"
    fail "golden regression test passed against the pre-fix tree (see $LOG)"
fi
grep -q "TypeError" /tmp/golden_prefix.out || {
    echo "golden failure on the pre-fix tree did not show the TypeError; output:" >> "$LOG"
    tail -8 /tmp/golden_prefix.out >> "$LOG"
    fail "pre-fix golden failure was not the documented crash (see $LOG)"
}
rm -rf /tmp/prefix-golden

# 7) stage the golden regression test in a world-writable scratch dir and
#    require it to pass against the repaired tree (imports resolve to
#    /app/src via SYMPY_SRC, so the test exercises precisely the tree the
#    agent edited). Staging in scratch rather than overwriting the tree's
#    copy keeps the verifier independent of the ownership of files inside
#    /app/src, which an agent running as root or as uid 1000 may set either
#    way.
rm -rf /tmp/golden-fixed
mkdir -p /tmp/golden-fixed || fail "cannot create scratch dir for the golden test"
cp /opt/golden/test_solveset.py /tmp/golden-fixed/test_solveset.py \
    || fail "cannot stage the golden regression test"
chmod -R a+rwX /tmp/golden-fixed
if ! ( cd /tmp/golden-fixed && SYMPY_SRC=/app/src python3 -m pytest \
        'test_solveset.py::test_nonlinsolve_sign' \
        -p no:cacheprovider > /tmp/golden_fixed.out 2>&1 ); then
    tail -25 /tmp/golden_fixed.out >&2
    fail "golden regression test did not pass on the repaired tree (see /tmp/golden_fixed.out)"
fi
grep -q "1 passed" /tmp/golden_fixed.out || {
    tail -15 /tmp/golden_fixed.out >&2
    fail "golden regression run did not report 1 passed (see /tmp/golden_fixed.out)"
}
rm -rf /tmp/golden-fixed

# 8) pre-existing nonlinsolve tests must stay green on the repaired tree.
if ! ( cd /app/src && python3 -m pytest -p no:cacheprovider -q \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_basic' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_abs' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_positive_dimensional' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_polysys' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_using_substitution' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_complex' \
        'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_radical' \
        'sympy/solvers/tests/test_solveset.py::test_raise_exception_nonlinsolve' \
        > /tmp/existing.out 2>&1 ); then
    tail -30 /tmp/existing.out >&2
    fail "existing nonlinsolve tests failed on the repaired tree (see /tmp/existing.out)"
fi
grep -q "8 passed" /tmp/existing.out || {
    tail -15 /tmp/existing.out >&2
    fail "existing nonlinsolve run did not report 8 passed (see /tmp/existing.out)"
}

# 9) hidden cases: same code path, inputs the upstream regression test does
#    not use. Each runs against the repaired tree and must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stderr:" >> "$LOG"
        head -15 "$work/stderr.txt" >> "$LOG"
        head -15 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected at least 3"

echo "PASS: pins, provenance, fix-unreachable, scope, deliverables, import resolution, repro both directions, golden both directions, existing nonlinsolve tests, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0