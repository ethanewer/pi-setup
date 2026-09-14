#!/bin/bash
# Verifier for alewife-dune: proves the agent fixed the ECDSA raw<->DER
# signature-conversion stack overflow in the real Mbed-TLS/mbedtls tree at
# /app/src, and that the agent's OWN failing reproduction is genuine.
#
#  0) trust anchors: toolchain sha256-pinned at image build time (detects
#     stub make/gcc); golden regression cases arrive via the host-side /tests
#     mount, which the agent never sees;
#  1) provenance: HEAD == pinned parent commit; the fix commit is not in the
#     object store; every tracked file except the two in-scope files is
#     byte-identical to the pinned commit; no untracked non-ignored files;
#  2) deliverables: /app/summary.md non-empty; the reproduction in
#     tests/suites/test_suite_psa_crypto_util.data parses as a genuine
#     oversized-coordinate case in BOTH directions;
#  3) the agent's reproduction must PASS on the repaired tree;
#  4) the agent's reproduction must FAIL on the pre-fix tree concept (a
#     byte-copy of the tree with library/psa_util.c restored from the pinned
#     commit and rebuilt);
#  5) the upstream golden regression test (the two 544-bit cases the fix
#     commit added; shipped as /tests/golden/golden_cases.data, which is
#     mounted ONLY for the verifier, never baked into the agent image) must
#     pass 43/43, both 544-bit cases printing PASS; the golden data is
#     reconstructed here as the pinned parent's 41 cases + those two, so
#     the run is exactly the fix commit's own test suite;
#  6) the project's own existing suites test_suite_psa_crypto and
#     test_suite_pk must still pass on the repaired tree;
#  7) at least two authored hidden cases (ship four) exercising the same code
#     path from inputs the upstream test does not use (560-bit both
#     directions; 528-bit boundary success both directions).
#
# Every rebuild below rm -rf's the generated suite sources and binaries
# first, so nothing an agent planted under git-ignored build paths survives,
# and the runs execute only binaries the verifier built itself.
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

PARENT=d1615b814af7136595927ec98d20f5f873a9f729
FIX=6bba0a8355db632f7287905ec577483979c47905
GIT=git
DATA=tests/suites/test_suite_psa_crypto_util.data
SUITE=test_suite_psa_crypto_util
GOLDEN=/tests/golden/golden_cases.data

# 0) integrity anchors. Everything the verifier builds or runs must be the
#    pinned toolchain (sha256'd at image build time into /opt/pins.sha256);
#    a substituted `make`, `gcc`, `cc`, `python3` or `git` fails here
#    before any build happens. The golden regression cases come from the
#    host-side /tests mount (never stored in the agent image), so they
#    cannot be tampered with from inside the container.
if ! ( cd / && sha256sum -c /opt/pins.sha256 > /dev/null 2>&1 ); then
    fail "toolchain integrity check failed (substituted binary; see /opt/pins.sha256)"
fi
[ -f "$GOLDEN" ] || fail "$GOLDEN missing from the verifier mount"

cd /app/src || fail "/app/src is missing"

# Purge EVERY build artifact the agent could have planted or left stale
# before any build runs. Object files, archives, generated suite sources,
# generated data (tests/*.datax), binaries and __pycache__ are all
# git-ignored, so the provenance hash check cannot see them, and a stale
# `make` would happily keep using them: an agent can compile a FIXED
# psa_util.o once, then restore the BUGGY source and leave the planted
# object to be linked in by the verifier's own `make`. git clean -fdx
# removes all ignored/untracked files (every one of them is regenerable
# by the project's own build), so everything the verifier builds from now
# on is compiled from the tracked sources it just hashed.
"$GIT" clean -fdx -q || fail "git clean -fdx failed on /app/src"
"$GIT" -C framework clean -fdx -q 2>/dev/null || true

# 1) provenance.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned parent $PARENT"
fi
if "$GIT" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "fix commit $FIX is reachable from the object store (answer leak)"
fi

# Scope: exactly the two in-scope files may differ from the pinned commit,
# byte-for-byte (hash the on-disk bytes, not git status, so assume-unchanged
# tricks cannot hide a dirty file); no untracked non-ignored file may exist.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        library/psa_util.c|tests/suites/test_suite_psa_crypto_util.data) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if "$GIT" ls-files -s -- "$f" | grep -q "^160000"; then
                # gitlink (submodule): the submodule working tree must still
                # be at the commit the parent records for it.
                have=$(git -C "$f" rev-parse HEAD 2>/dev/null || true)
                if [ "$have" != "$want" ]; then
                    echo "out-of-scope submodule checkout moved: $f" >> "$LOG"; ok=0
                fi
            else
                if [ -L "$f" ]; then
                    have=$(printf '%s' "$(readlink "$f")" | "$GIT" hash-object --stdin 2>/dev/null || true)
                else
                    have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
                fi
                if [ -z "$have" ] || [ "$have" != "$want" ]; then
                    echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
                fi
            fi
            ;;
    esac
done < <("$GIT" ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <("$GIT" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG" >&2
    fail "working tree modified outside the fix scope (see $LOG)"
fi

# 2) deliverables: change summary exists; reproduction is genuine.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
python3 /tests/repro_check.py "$DATA" > /tmp/repro_check.out 2>&1 || {
    echo "reproduction is not genuine; repro_check said:" >> "$LOG"
    cat /tmp/repro_check.out >> "$LOG"
    fail "the reproduction in $DATA is not a genuine oversized-coordinate case in both directions (see $LOG)"
}
cat /tmp/repro_check.out
# The first oversized raw->DER raw payload, for the embedded-bytes checks.
EMBEDHEX=$(python3 - "$DATA" <<'PY'
import re, sys
for ln in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r'ecdsa_raw_to_der:(\d+):"([0-9a-fA-F]*)"', ln.strip())
    if m and int(m.group(1)) >= 529:
        print(m.group(2)[:32]); break
PY
)
[ -n "$EMBEDHEX" ] || fail "could not extract an oversized raw->DER payload for the embed check"

SUITE_BIN=tests/$SUITE
SUITE_SRC=tests/$SUITE.c
rebuild_suite() { # $1 = data-file to plant (cp'd over $DATA first by caller)
    rm -f "$SUITE_BIN" "$SUITE_SRC" "tests/$SUITE.datax"
    make -C tests "$SUITE" > /tmp/suite_build.log 2>&1 || {
        echo "suite build failed; tail:" >> "$LOG"
        tail -30 /tmp/suite_build.log >> "$LOG"
        fail "make -C tests $SUITE failed (see $LOG)"
    }
    [ -x "$SUITE_BIN" ] || fail "suite binary $SUITE_BIN not produced"
    if [ "$(od -An -tx1 -N4 "$SUITE_BIN" | tr -d ' \n')" != "7f454c46" ]; then
        fail "suite binary $SUITE_BIN is not a real ELF executable (planted script?)"
    fi
}
run_suite() { # $1 = logfile; requires PASSED (N / N) and no FAILED and rc==0
    local logf="$1"
    if ! "$SUITE_BIN" > "$logf" 2>&1; then
        echo "suite run failed rc=$?; tail:" >> "$LOG"
        tail -25 "$logf" >> "$LOG"
        fail "suite run failed (see $LOG)"
    fi
    if grep -q "FAILED" "$logf"; then
        echo "suite run contains FAILED test lines; lines:" >> "$LOG"
        grep "FAILED" "$logf" >> "$LOG"
        fail "suite run contains failing tests (see $LOG)"
    fi
    grep -E "PASSED \(([0-9]+) / \1 tests" "$logf" | head -1 > /tmp/passed_line.txt \
        || fail "suite run did not report a PASSED (N / N tests) summary"
    cat /tmp/passed_line.txt
}

# 3) The verifier rebuilds the library itself from the agent's source, so
#    the runs below measure the tree as it stands (changed psa_util.c -> new
#    libmbedcrypto.a), not any stale objects the agent may have left behind.
if ! make -j1 lib > /tmp/lib_build.log 2>&1; then
    echo "make -j1 lib failed on the agent's tree; tail:" >> "$LOG"
    tail -30 /tmp/lib_build.log >> "$LOG"
    fail "make -j1 lib failed on the agent's tree (see $LOG)"
fi

# agent's reproduction on the REPAIRED tree: rebuild from the agent's
#    .data and run; must pass.
rebuild_suite
if ! grep -Fq "$EMBEDHEX" "tests/$SUITE.datax"; then
    fail "rebuilt suite data (tests/$SUITE.datax) does not contain the agent's oversized raw->DER payload"
fi
run_suite /tmp/run_repro_fixed.log
echo "agent reproduction PASSES on the repaired tree"

# 4) agent's reproduction on the PRE-FIX tree concept: byte-copy the tree,
#    restore library/psa_util.c from the pinned commit's own blob, rebuild
#    everything, and require the run to FAIL (the reproduction must be a
#    real failing reproduction).
rm -rf /tmp/prefix
cp -a /app/src /tmp/prefix
"$GIT" show "$PARENT:library/psa_util.c" > /tmp/prefix/library/psa_util.c \
    || fail "cannot restore pristine psa_util.c for the pre-fix concept"
touch /tmp/prefix/tests/suites/test_suite_psa_crypto_util.data
( cd /tmp/prefix \
  && rm -f tests/test_suite_psa_crypto_util tests/test_suite_psa_crypto_util.c tests/test_suite_psa_crypto_util.datax \
  && make -j1 lib > /tmp/prefix_lib.log 2>&1 \
  && make -C tests test_suite_psa_crypto_util > /tmp/prefix_suite.log 2>&1 ) \
  || { echo "pre-fix concept build failed; tail:" >> "$LOG"
       tail -20 /tmp/prefix_lib.log /tmp/prefix_suite.log >> "$LOG"
       fail "pre-fix concept tree failed to build (see $LOG)"; }
grep -Fq "$EMBEDHEX" /tmp/prefix/tests/test_suite_psa_crypto_util.datax \
    || fail "pre-fix concept suite data does not contain the agent's oversized payload"
/tmp/prefix/tests/test_suite_psa_crypto_util > /tmp/run_prefix.log 2>&1
prefix_rc=$?
if [ "$prefix_rc" -eq 0 ]; then
    echo "pre-fix concept run rc=0; output tail:" >> "$LOG"
    tail -15 /tmp/run_prefix.log >> "$LOG"
    fail "the agent's reproduction PASSES on the pre-fix tree — it does not reproduce the bug"
fi
echo "pre-fix concept run rc=$prefix_rc (expected non-zero): the agent's reproduction fails on the unfixed tree"
tail -4 /tmp/run_prefix.log
rm -rf /tmp/prefix

# 5) upstream golden regression test on the repaired tree: reconstruct the
#    fix commit's own 43-case data as the pinned parent's 41 cases + the two
#    544-bit regression cases (so the run is exactly the upstream golden
#    suite, independent of anything the agent wrote into the data file).
"$GIT" show "$PARENT:$DATA" > "$DATA" \
    || fail "cannot restore the parent's test data for the golden run"
cat "$GOLDEN" >> "$DATA"
rebuild_suite
run_suite /tmp/run_golden.log
for t in "ECDSA Raw -> DER, very large input (544-bit)" \
         "ECDSA DER -> Raw, very large input (544-bit)"; do
    grep -F "$t" /tmp/run_golden.log | grep -q PASS || {
        echo "golden case not PASS in output; lines:" >> "$LOG"
        grep -F "$t" /tmp/run_golden.log >> "$LOG"
        fail "golden case '$t' did not print PASS (see $LOG)"
    }
done
grep -q "43 / 43" /tmp/run_golden.log || fail "golden run did not report 43/43 tests"
echo "upstream golden regression test PASSES (43/43, both 544-bit cases)"

# 6) the project's own existing suites on the repaired tree.
for s in test_suite_psa_crypto test_suite_pk; do
    rm -f "tests/$s" "tests/$s.c"
done
make -C tests test_suite_psa_crypto test_suite_pk > /tmp/exist_build.log 2>&1 || {
    tail -30 /tmp/exist_build.log >> "$LOG"
    fail "make -C tests test_suite_psa_crypto test_suite_pk failed (see $LOG)"
}
./tests/test_suite_psa_crypto > /tmp/run_psa.log 2>&1 || fail "test_suite_psa_crypto failed to run"
./tests/test_suite_pk > /tmp/run_pk.log 2>&1 || fail "test_suite_pk failed to run"
grep -q "PASSED (1945 / 1945" /tmp/run_psa.log || fail "test_suite_psa_crypto did not pass 1945/1945"
grep -q "PASSED (407 / 407" /tmp/run_pk.log || fail "test_suite_pk did not pass 407/407"
grep -q "FAILED" /tmp/run_psa.log && fail "test_suite_psa_crypto had failing tests" || true
grep -q "FAILED" /tmp/run_pk.log && fail "test_suite_pk had failing tests" || true
echo "existing suites green: test_suite_psa_crypto 1945/1945, test_suite_pk 407/407"

# 7) authored hidden cases: same code path, inputs the upstream test does
#    not use (560-bit oversized both directions; 528-bit boundary success
#    both directions). Each is run against golden+its-fragment, rebuilt
#    fresh, and must print PASS.
CASES=0
for case in /tests/hidden/*/; do
    frag="$case/fragment"
    [ -f "$frag" ] || fail "hidden case $case: missing fragment file"
    title=$(head -1 "$frag")
    [ -n "$title" ] || fail "hidden case $case: empty fragment"
    # Full suite on the repaired tree: the pinned parent's 41 cases + the
    # two golden 544-bit regression cases + this hidden fragment (44 cases),
    # so hidden runs cover the whole suite, not just the new cases.
    "$GIT" show "$PARENT:$DATA" > "$DATA"
    cat "$GOLDEN" >> "$DATA"
    { echo; cat "$frag"; } >> "$DATA"
    rebuild_suite
    run_suite /tmp/run_hidden.log
    grep -F "$title" /tmp/run_hidden.log | grep -q PASS || {
        echo "hidden case line not PASS; output lines:" >> "$LOG"
        grep -F "$title" /tmp/run_hidden.log >> "$LOG"
        fail "hidden case '$title' did not print PASS (see $LOG)"
    }
    echo "hidden case PASS: $title"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected at least 2"

echo "PASS: provenance, deliverables, agent reproduction (fails pre-fix, passes fixed), golden 43/43, existing suites, and $CASES hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0