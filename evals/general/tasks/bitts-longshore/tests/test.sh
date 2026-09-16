#!/bin/bash
# Verifier for bitts-longshore: an upstream-clone debugging task on sympy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# symbolic modulo expressions silently change value when a symbol carries an
# integer assumption (the inner residue of a nested Mod ends up squared).
#
#   0. integrity anchors: the golden regression test and the pristine pre-fix
#      sympy/core/mod.py still have the sha256 pinned at image build time;
#   1. provenance: HEAD is still the pinned parent commit, the upstream fix
#      commit is not reachable from the working clone, the tree is
#      byte-identical to the parent commit except for the single source file
#      the bug lives in (sympy/core/mod.py), and no untracked file appeared;
#   2. deliverables: /app/repro.sh (executable, the agent's OWN failing
#      reproduction) and /app/summary.md;
#   3. the agent's reproduction, run against a scratch copy of the REPAIRED
#      tree (must exit 0) and against a scratch copy with the pristine
#      pre-fix mod.py restored (must exit non-zero) - proves the symptom is
#      real and the reproduction targets it;
#   4. the project's own regression test for this bug (test_Mod from
#      sympy/core/tests/test_arit.py at the FIX commit, extracted at image
#      build time into /opt/golden via a throwaway clone, sha256-pinned):
#      must PASS on the repaired tree and FAIL on the pre-fix copy;
#   5. the project's own existing arithmetic test module test_arit.py with
#      the regression test planted: the whole module must pass, proving the
#      fix broke nothing else;
#   6. three authored hidden cases that reach the same code path from inputs
#      the upstream test does not use (different moduli/coefficients, an
#      even-assumption trigger, merged multiplier factors), each required to
#      PASS on the repaired tree and FAIL on the pre-fix copy.
#
# Reward is binary and written on every exit path (trap below). All pytest
# runs use the absolute python path and a pinned PATH so a wrapper planted by
# the agent cannot fake a green run, and PYTHONNOUSERSITE blocks user-site
# import injection.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=648f6cfb88b83e58655499523fb6cede213d10c2
FIX=f1b4be1bf83baee7e9ac116e81cdae1f30c5d1cd
GOLDEN_SHA=19fa74173e55074d202245ce33a6929e38920c07ae49c1a17e61edf10178cf96
PREFIX_SHA=5c37e9b61dabe0059cd38a0baad0d6c05b9844bcc8d25d0c84b33019232ef7d8
PY=/usr/local/bin/python3
RUNTEST_ENV="PATH=/usr/local/bin:/usr/bin:/bin"

cd /app/src || fail "/app/src is missing"

# run_pytest TREE OUT args...  -- runs pytest from TREE importing sympy from
# TREE, with an absolute interpreter and a pinned PATH.
run_pytest() {
    tree="$1"; out="$2"; shift 2
    ( cd "$tree" && PYTHONPATH="$tree" env PATH=/usr/local/bin:/usr/bin:/bin \
        "$PY" -m pytest "$@" -p no:cacheprovider > "$out" 2>&1 )
}

# 0) integrity anchors: the verifier hardcodes the expected hashes (this
#    script is mounted read-only at /tests), so replacing /opt/golden or
#    /opt/prefix - even by an agent with write access to /opt - cannot fake
#    a green run or unfalsify the pre-fix direction.
have_golden=$(sha256sum /opt/golden/test_arit.py | awk '{print $1}')
have_prefix=$(sha256sum /opt/prefix/mod.py | awk '{print $1}')
if [ "$have_golden" != "$GOLDEN_SHA" ] || [ "$have_prefix" != "$PREFIX_SHA" ]; then
    fail "integrity check failed (golden=$have_golden prefix=$have_prefix; expected golden=$GOLDEN_SHA prefix=$PREFIX_SHA)"
fi
[ -x "$PY" ] || fail "python interpreter $PY is missing"

# 1) provenance: no commits added, the upstream fix commit is not reachable
#    from this object store (an agent that fetched or grafted the answer
#    earns 0), and the working tree differs from the parent commit in at
#    most the one source file the bug lives in.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

#    Byte-level scope check: every tracked file EXCEPT sympy/core/mod.py must
#    have worktree bytes identical to its parent blob (git hash-object reads
#    raw bytes, so assume-unchanged / skip-worktree / index tricks cannot
#    hide a change), and there must be no untracked non-ignored file (a
#    planted conftest.py or helper could otherwise supply the expected
#    behaviour while the buggy code stays in place).
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        sympy/core/mod.py) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree bytes differ from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree differs from the pinned commit outside sympy/core/mod.py (see $LOG)"
fi
if [ "$(git hash-object -- sympy/core/mod.py)" = "$(git rev-parse "$PARENT:sympy/core/mod.py")" ]; then
    fail "sympy/core/mod.py is unchanged (no fix was implemented)"
fi

# 2) deliverables: the agent's own reproduction script and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 3) scratch copies of the tree: repaired (as delivered) and pre-fix (parent
#    mod.py restored from the pinned pristine bytes).
rm -rf /tmp/fixed /tmp/prefix
cp -a /app/src /tmp/fixed || fail "cannot copy /app/src to /tmp/fixed"
cp -a /app/src /tmp/prefix || fail "cannot copy /app/src to /tmp/prefix"
cp /opt/prefix/mod.py /tmp/prefix/sympy/core/mod.py || fail "cannot restore pre-fix mod.py"
want=$(git rev-parse "$PARENT:sympy/core/mod.py")
have=$(git -C /tmp/prefix hash-object /tmp/prefix/sympy/core/mod.py)
if [ "$have" != "$want" ]; then
    fail "pre-fix restoration failed: hash $have != parent blob $want"
fi

# 4) the agent's reproduction, both directions: must pass on the repaired
#    tree and fail on the pre-fix copy. An exit 0 on the pre-fix copy means
#    the reproduction is fake/hardcoded or the symptom is not the bug.
if ! bash /app/repro.sh /tmp/fixed > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree (rc=$?); stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if bash /app/repro.sh /tmp/prefix > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro PASSED against the PRE-FIX tree (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 5) golden: the upstream regression test node, PASS on the repaired tree
#    and FAIL on the pre-fix copy.
cp /opt/golden/test_arit.py /tmp/fixed/sympy/core/tests/test_arit.py || fail "cannot plant golden into repaired tree"
cp /opt/golden/test_arit.py /tmp/prefix/sympy/core/tests/test_arit.py || fail "cannot plant golden into pre-fix tree"
run_pytest /tmp/fixed /tmp/golden_fixed.log 'sympy/core/tests/test_arit.py::test_Mod'
rc=$?
if [ $rc -ne 0 ] || ! grep -qE '1 passed' /tmp/golden_fixed.log; then
    tail -25 /tmp/golden_fixed.log
    fail "upstream regression test test_Mod did not pass on the repaired tree (see log)"
fi
run_pytest /tmp/prefix /tmp/golden_prefix.log 'sympy/core/tests/test_arit.py::test_Mod'
rc=$?
if [ $rc -eq 0 ] || ! grep -qE 'FAILED.*test_Mod' /tmp/golden_prefix.log; then
    tail -25 /tmp/golden_prefix.log
    fail "upstream regression test test_Mod did not FAIL on the pre-fix tree (see log)"
fi

# 6) the project's own existing arithmetic module, with the regression test
#    planted: must pass in full (101 passed, 2 xfailed at the pinned tree).
run_pytest /tmp/fixed /tmp/module.log sympy/core/tests/test_arit.py
rc=$?
if [ $rc -ne 0 ]; then
    tail -30 /tmp/module.log
    fail "the project's own test_arit.py suite did not pass with the repaired tree (see log)"
fi
if ! grep -qE '[0-9]+ passed' /tmp/module.log; then
    tail -10 /tmp/module.log
    fail "test_arit.py run reported no passing tests (see log)"
fi

# 7) authored hidden cases: each must PASS on the repaired tree and FAIL on
#    the pre-fix copy. Distinct inputs the upstream regression test does not
#    use: different moduli and coefficients, an even-assumption trigger, and
#    merged multiplier factors.
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    pyfile=$(ls "$case"/*.py 2>/dev/null | head -1)
    [ -n "$pyfile" ] || fail "hidden case $name: no .py file found"
    fname=$(basename "$pyfile")

    cp "$pyfile" "/tmp/fixed/sympy/core/tests/$fname" || fail "hidden case $name: cannot plant into repaired tree"
    run_pytest /tmp/fixed "/tmp/hc-$name-fixed.log" "sympy/core/tests/$fname"
    rc=$?
    if [ $rc -ne 0 ] || ! grep -qE '1 passed' "/tmp/hc-$name-fixed.log"; then
        tail -20 "/tmp/hc-$name-fixed.log" >&2
        fail "hidden case $name did not pass on the repaired tree (see log)"
    fi
    rm -f "/tmp/fixed/sympy/core/tests/$fname"

    cp "$pyfile" "/tmp/prefix/sympy/core/tests/$fname"
    run_pytest /tmp/prefix "/tmp/hc-$name-prefix.log" "sympy/core/tests/$fname"
    rc=$?
    if [ $rc -eq 0 ] || ! grep -qE 'FAILED' "/tmp/hc-$name-prefix.log"; then
        echo "hidden case $name on the PRE-FIX copy (rc=$rc):" >> "$LOG"
        tail -15 "/tmp/hc-$name-prefix.log" >> "$LOG"
        fail "hidden case $name did not fail on the pre-fix copy (see $LOG)"
    fi
    rm -f "/tmp/prefix/sympy/core/tests/$fname"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected at least 2"

echo "PASS: anchors, provenance, byte-scope, deliverables, repro both directions, golden both directions, existing test_arit.py suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0