#!/bin/bash
# Verifier for corvette-towpath: proves the agent's fix in the real
# Z3Prover/z3 tree at /app/src. The bug (upstream issue #10608): the fpa2bv
# conversion of fp.fma computes an IEEE 754 encoding that is one ulp off for
# some binary16 (5,11) operand triples: the h2 (second) rounding step of
# mk_fma() builds its sticky reduction from the FIRST step's discarded-bit
# range (sticky_h1) instead of its own (sticky_h2), so some inexact results
# round as if their late bits were zero. For a fully pinned half-precision
# query the parent answers `sat` (wrong; the operands determine the result)
# where it must answer `unsat`.
#
# The verifier:
#   1. runs the AGENT'S OWN reproduction (/app/reproduce.sh) against the
#      baked-in pristine pre-fix binary (/opt/pre-fix/z3) - must print `sat`
#      (the reproduction genuinely fails on the unpatched tree);
#   2. asserts provenance: HEAD is still the pinned parent commit, the fix
#      commit is not reachable, every tracked file except
#      src/ast/fpa/fpa2bv_converter.cpp is identical to its parent blob
#      (filter-aware), there are no untracked non-ignored files, and
#      /app/summary.md exists and is non-empty;
#   3. rebuilds the solver binary (build/z3) from the agent's tree with the
#      fixed source recompiled, then runs the agent's reproduction against it
#      - must print `unsat`;
#   4. plants the project's own regression test (the fix-commit version of
#      src/test/smt_context.cpp, baked into /opt/golden at image build time,
#      sha256-pinned here so a tampered golden copy is rejected), rebuilds
#      the project's own test harness offline, and runs the module
#      `smt_context` - must pass;
#   5. runs the project's ENTIRE existing unit suite (./build/test-z3 -a) -
#      must pass with 0 failed;
#   6. runs authored hidden SMT cases (half-precision fp.fma operand pairs
#      whose bit patterns and expected encodings differ from the visible
#      reproduction and from each other) through the rebuilt solver - each
#      must print exactly `unsat` and exit 0, and each must print exactly
#      `sat` against the pre-fix binary (proving every hidden case bites the
#      bug).
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

PARENT=e950cd371c3ca16823079feded145bc6ce3feb95
FIX=8d32b2b02ab31c5cd293362866fa32f6eab75e09
GOLDEN_SHA=b4fc0a18327fe9a85d41927b50417f319f256185b7d41f4e483a44fdcaacfd0a
SRCFILE=src/ast/fpa/fpa2bv_converter.cpp
CRLFFILE=src/math/simplex/model_based_opt.cpp

cd /app/src || fail "/app/src is missing"

# 0) the agent's own reproduction deliverable must exist and run.
[ -f /app/reproduce.sh ] || fail "/app/reproduce.sh is missing"
[ -x /app/reproduce.sh ] || fail "/app/reproduce.sh is not executable"
grep -q 'Z3_BIN' /app/reproduce.sh || fail "/app/reproduce.sh does not reference Z3_BIN"
grep -q 'fpa2bv' /app/reproduce.sh || fail "/app/reproduce.sh does not steer the query onto the fpa2bv conversion path"

# 1) the reproduction must genuinely fail on the unpatched tree: run it with
#    the pristine PRE-FIX binary. The pre-fix binary is a root-owned copy
#    baked into the image at build time; it is also probed directly with the
#    pinned regression query so a broken or replaced copy cannot silently
#    corrupt this check.
cat > /tmp/pre_fix_probe.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(declare-const xb (_ BitVec 16))
(declare-const yb (_ BitVec 16))
(assert (= x ((_ to_fp 5 11) xb)))
(assert (= y ((_ to_fp 5 11) yb)))
(assert (= xb #b1000001111000111))
(assert (= yb #b0011110111000000))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.fma RNE x y x)) #x889b)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
out=$(Z3_BIN=/opt/pre-fix/z3 /app/reproduce.sh 2>/tmp/repro-prefix-err.txt)
if [ "$out" != "sat" ]; then
    echo "reproduction (pre-fix binary) printed: '$out'" >> "$LOG"
    head -5 /tmp/repro-prefix-err.txt >> "$LOG"
    fail "the agent's reproduction must print exactly 'sat' against the pre-fix binary (see $LOG)"
fi
if [ "$(/opt/pre-fix/z3 /tmp/pre_fix_probe.smt2)" != "sat" ]; then
    fail "the baked pre-fix binary is not the expected buggy build (probe did not answer sat)"
fi

# 2) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 3) the upstream fix commit must not be reachable (an agent that fetched and
#    applied it would have it in the object store).
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone"
fi

# 4) scope: every change must live in exactly the one source file the bug is
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

# 5) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 6) rebuild the solver binary from the agent's tree (proves the tree
#    compiles and the binary that runs the hidden cases is the agent's). The
#    object of the fixed source is deleted and the source re-touched, so the
#    object is recompiled from the agent's actual bytes even against
#    future-mtime fakes, and the old binary is deleted so the link is forced.
touch "$SRCFILE"
rm -f build/z3 build/test-z3 \
      build/src/ast/fpa/CMakeFiles/fpa.dir/fpa2bv_converter.cpp.o
if ! cmake --build build --target shell -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cmake shell rebuild failed on the agent's tree (see $LOG.build)"
fi
[ -x build/z3 ] || fail "build/z3 not produced by the rebuild"
./build/z3 --version > /dev/null 2>&1 || fail "build/z3 does not run"
rm -f /tmp/pre_fix_probe.smt2

# 7) the agent's own reproduction must now print the correct verdict.
out=$(Z3_BIN=/app/src/build/z3 /app/reproduce.sh 2>/tmp/repro-fixed-err.txt)
if [ "$out" != "unsat" ]; then
    echo "reproduction (repaired binary) printed: '$out'" >> "$LOG"
    head -5 /tmp/repro-fixed-err.txt >> "$LOG"
    fail "the agent's reproduction must print exactly 'unsat' against the repaired binary (see $LOG)"
fi

# 8) plant the upstream regression test for this bug (golden bytes from the
#    fix commit, extracted at image build time into /opt/golden; never part
#    of this task tree) and rebuild the project's test harness offline. The
#    post-plant bytes are sha256-pinned here: an agent that edited
#    /opt/golden (both run as root in this container) would fail this check
#    rather than pass a tampered test.
bash /app/plant_golden.sh >> "$LOG" 2>&1 || fail "cannot plant the golden regression test"
if [ "$(sha256sum src/test/smt_context.cpp | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    fail "golden regression test bytes do not match the pinned upstream file"
fi
rm -f build/src/test/CMakeFiles/test-z3.dir/smt_context.cpp.o
if ! cmake --build build --target test-z3 -j1 > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cmake test-z3 rebuild failed after planting the regression test (see $LOG.build2)"
fi

# 9) the upstream regression test must pass. (On the unfixed tree this test
#    fails with an assertion violation: the parent answers `sat` to a fully
#    pinned query that must be `unsat`.)
if ! ./build/test-z3 smt_context > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "PASS" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "smt_context regression test did not actually run and pass (see /tmp/golden.out)"
}

# 10) the project's ENTIRE existing unit suite must stay green.
if ! ./build/test-z3 -a > /tmp/suite.out 2>&1; then
    tail -40 /tmp/suite.out >&2
    fail "the project's full unit suite failed (see /tmp/suite.out)"
fi
if ! grep -Eq ", 0 failed," /tmp/suite.out; then
    tail -10 /tmp/suite.out >&2
    fail "the project's full unit suite did not report 0 failed (see /tmp/suite.out)"
fi

# 11) authored hidden SMT cases: half-precision fp.fma operand pairs that
#     reach the same broken path with inputs the upstream test and the
#     visible reproduction do not use. Each must print exactly `unsat` on
#     the rebuilt solver and exit 0, and exactly `sat` against the pre-fix
#     binary. (Every case is answered `sat` by the unfixed tree.)
if grep -rqE '#b(1000001111000111|0011110111000000)' /tests/hidden/; then
    fail "a hidden case reuses the visible/upstream operand pair"
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
    pre=$(/opt/pre-fix/z3 "$q" 2>/dev/null)
    if [ "$pre" != "sat" ]; then
        echo "hidden case $name: pre-fix answer was '$pre', expected exactly 'sat'" >> "$LOG"
        fail "hidden case $name: does not bite the bug (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: reproduction (sat pre-fix / unsat post-fix), provenance, /app/summary.md, rebuild, upstream regression test, full unit suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0