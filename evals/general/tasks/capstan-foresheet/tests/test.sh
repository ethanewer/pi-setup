#!/bin/bash
# Verifier for capstan-foresheet: proves the agent's fix in the real
# Z3Prover/z3 tree at /app/src. The bug (upstream issue #10609): the fpa2bv
# conversion of fp.rem widens the operand significands by max_exp_diff bits,
# but a subnormal divisor can lower the normalized exponent far enough that
# the exponent difference shifts the dividend's high bits out, so the
# computed IEEE remainder is wrong (e.g. -0.0 instead of the true value) and
# fully pinned queries that must answer `unsat` answer `sat`. The verifier
#   1. asserts provenance: HEAD is still the pinned parent commit, every
#      tracked file except src/ast/fpa/fpa2bv_converter.cpp is identical to
#      its parent blob (filter-aware; the repo's `* text=auto` attribute
#      means src/math/simplex/model_based_opt.cpp legitimately carries raw
#      bytes different from its blob after checkout, so that one file is
#      compared via git's own diff instead of raw bytes), there are no
#      untracked non-ignored files, and /app/summary.md exists and is
#      non-empty;
#   2. rebuilds the solver binary (build/z3) from the agent's tree;
#   3. plants the upstream regression test (golden bytes from /opt/golden,
#      extracted from the fix commit at image build time, never part of this
#      task tree) together with the two one-line registrations the fix commit
#      performs, rebuilds the project's own test harness offline;
#   4. runs the project's OWN regression test through the project's own
#      runner (./build/test-z3 fpa) - must pass;
#   5. runs the project's ENTIRE existing unit suite (./build/test-z3 -a) -
#      must pass with 0 failed;
#   6. runs three authored hidden SMT cases (half-precision fp.rem operand
#      pairs whose bit patterns, signs and expected encodings differ from the
#      visible reproduction) through the rebuilt solver - each must print
#      exactly `unsat` and exit 0.
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

PARENT=d1f10234c50a49ee1cc7d08c87a680daf430017c
FIX=384d2d881f544e0f3abfa21e0e3ebe6beb9821d7
GOLDEN_SHA=b5bed2720afa7cdbba4ad9ddc22ed68f03f84b758a1f9c9a5a8147d3530ddba9
SRCFILE=src/ast/fpa/fpa2bv_converter.cpp
CRLFFILE=src/math/simplex/model_based_opt.cpp

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) the upstream fix commit must not be reachable (an agent that fetched and
#    applied it would have it in the object store).
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone"
fi

# 3) scope: every change must live in exactly the one source file the bug is
#    in (src/ast/fpa/fpa2bv_converter.cpp, discovered by the agent, not named
#    in the instruction). Two complementary passes.
#    Pass A (filter-aware, single git call): `git diff --name-only` against
#    the pinned commit. The repository ships a `.gitattributes` with
#    `* text=auto`, so src/math/simplex/model_based_opt.cpp (whose blob
#    carries CRLF line endings) has raw worktree bytes that differ from its
#    blob after checkout while git itself considers the file clean; a diff
#    against the pinned commit is immune to that.
#    Pass B (raw bytes, every tracked file except the CRLF-filtered one):
#    hash the actual worktree bytes of every other tracked file against the
#    pinned commit's own blob, so assume-unchanged / skip-worktree tricks
#    cannot hide a change. Any untracked non-ignored file fails too.
ok=1
changed=$(git diff --name-only "$PARENT" -- . 2>/dev/null || true)
for f in $changed; do
    if [ "$f" != "$SRCFILE" ]; then
        echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
    fi
done
while IFS= read -r -d '' f; do
    case "$f" in
        "$SRCFILE"|"$CRLFFILE") : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
            else
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi
case " $changed " in
    *" $SRCFILE "*) : ;;
    *) fail "the deliverable /app/src is unchanged (no fix was implemented)" ;;
esac

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5) rebuild the solver binary from the agent's tree (proves the tree
#    compiles and the binary that runs the hidden cases is the agent's).
if ! cmake --build build --target shell -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cmake shell rebuild failed on the agent's tree (see $LOG.build)"
fi
[ -x build/z3 ] || fail "build/z3 not produced by the rebuild"
./build/z3 --version > /dev/null 2>&1 || fail "build/z3 does not run"

# 6) plant the upstream regression test for this bug (golden bytes from the
#    fix commit, extracted at image build time; never part of this task
#    tree) with the exact registrations the fix commit performs, and rebuild
#    the project's test harness offline.
bash /app/plant_golden.sh >> "$LOG" 2>&1 || fail "cannot plant the golden regression test"
if [ "$(sha256sum src/test/fpa.cpp | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    fail "golden regression test bytes do not match the pinned upstream file"
fi
if ! cmake --build build --target test-z3 -j1 > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cmake test-z3 rebuild failed after planting the regression test (see $LOG.build2)"
fi

# 7) the upstream regression test must pass. (On the unfixed tree this test
#    fails with an assertion violation: the parent answers `sat` to a fully
#    pinned query that must be `unsat`.)
if ! ./build/test-z3 fpa > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "PASS" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "fpa regression test did not actually run and pass (see /tmp/golden.out)"
}

# 8) the project's ENTIRE existing unit suite must stay green (the fpa module
#    is registered in this run too, since the harness was rebuilt with the
#    golden registration in place).
if ! ./build/test-z3 -a > /tmp/suite.out 2>&1; then
    tail -40 /tmp/suite.out >&2
    fail "the project's full unit suite failed (see /tmp/suite.out)"
fi
if ! grep -Eq ", 0 failed," /tmp/suite.out; then
    tail -10 /tmp/suite.out >&2
    fail "the project's full unit suite did not report 0 failed (see /tmp/suite.out)"
fi

# 9) three authored hidden SMT cases: half-precision fp.rem pairs that reach
#    the same broken path with inputs the upstream test does not use (none of
#    their operand patterns appears in the golden test). Each must print
#    exactly `unsat` and exit 0. (Every case answers `sat` on the unfixed
#    tree.)
if grep -rqE '#b(1110100000101010|1000000000010101)' /tests/hidden/; then
    fail "a hidden case reuses the upstream test's operand pair"
fi
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    q="$case/query.smt2"
    [ -f "$q" ] || fail "hidden case $name: missing query.smt2"
    out=$(./build/z3 "$q" 2>/tmp/hc-stderr.txt)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: z3 exited $rc; stderr:" >> "$LOG"
        head -8 /tmp/hc-stderr.txt >> "$LOG"
        fail "hidden case $name: z3 exited $rc (see $LOG)"
    fi
    if [ "$out" != "unsat" ]; then
        echo "hidden case $name: answer was '$out', expected exactly 'unsat'" >> "$LOG"
        fail "hidden case $name: wrong answer (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, rebuild, upstream regression test, full unit suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0