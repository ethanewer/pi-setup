#!/bin/bash
# Verifier for sill-barquentine: proves the agent's fix in the real
# duckdb/duckdb tree at /app/src by (1) asserting the verifier's own trust
# anchors (the golden regression test, the pristine pre-fix source and the
# pristine pre-fix CLI binary still have the sha256 pinned at image build
# time), (2) asserting provenance (HEAD still the pinned parent commit; the
# upstream fix commit is not reachable from this clone; every tracked file
# except the single source file the bug lives in is byte-identical to the
# parent commit; no stray untracked files; the bug's source file must
# actually differ), (3) requiring /app/repro.sh and /app/summary.md, (4)
# rebuilding the tree from the delivered source with the project's own ninja
# build, (5) running the agent's own reproduction against the repaired tree
# (must pass) and against the baked pristine pre-fix tree concept at
# /opt/prefix/tree (must fail - this proves the symptom is real and the
# reproduction targets it; the pre-fix CLI was built from the parent tree at
# image build time, since DuckDB's unity build records absolute /app/src
# include paths and a copied tree cannot be rebuilt faithfully offline), (6)
# planting the upstream project's own regression test for this bug (the
# NULL-sequence-options block the fix commit added to test/sql/catalog/
# sequence/test_sequence.test, extracted at image build time into
# /opt/golden, sha256-pinned) and running it with the project's own unittest
# runner, plus the whole test/sql/catalog/sequence/* directory, (7) running
# five authored hidden cases that reach the same parser path from inputs the
# upstream test does not use, each required to pass on the repaired tree and
# to fail on the pre-fix tree.
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

PARENT=b98263558bf0afb1f0eac0d559a0a6604bbd688c
FIX=115e593139967b82764c5452540c955962033438
GOLDEN_SHA=01e365fb0c7711d2f650c929e36a51263e60f23c038d759e5d0e8cd7689d2cc4
PREFIX_SHA=8492e3f206e6c4cffab182fc63b372134dbbc82204dceeb0561738fdf58103af
PREFIXCLI_SHA=aaa33843b1c4c295bf45a09cf646b0b12910de38910d50fce25571f1e27fecfc

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. An adversarial agent with write access to /opt (a
#    root trial) could otherwise replace the golden test with a lax copy or
#    replace the pristine pre-fix source/binary with already-fixed ones (so
#    the pre-fix direction checks fail to fail). The expected values are
#    hardcoded HERE, in the verifier script itself (mounted read-only).
#    Note: /opt/prefix/bin/duckdb and /opt/prefix/tree/build/release/duckdb
#    are byte-copies of the SAME pristine pre-fix CLI (both `cp`'d from the
#    parent build at image build time), so they share PREFIXCLI_SHA; assert
#    on both so the pre-fix tree binary actually used by the direction checks
#    cannot be swapped for a fixed one.
have_golden=$(sha256sum /opt/golden/test_sequence.test | awk '{print $1}')
have_prefix=$(sha256sum /opt/prefix/tree/src/parser/peg/transformer/transform_create_sequence.cpp | awk '{print $1}')
have_prefixcli=$(sha256sum /opt/prefix/bin/duckdb | awk '{print $1}')
have_prefixcli_tree=$(sha256sum /opt/prefix/tree/build/release/duckdb | awk '{print $1}')
if [ "$have_golden" != "$GOLDEN_SHA" ] || [ "$have_prefix" != "$PREFIX_SHA" ] \
   || [ "$have_prefixcli" != "$PREFIXCLI_SHA" ] || [ "$have_prefixcli_tree" != "$PREFIXCLI_SHA" ]; then
    fail "golden or pre-fix source/binary integrity check failed (golden=$have_golden prefix=$have_prefix prefixcli=$have_prefixcli prefixcli_tree=$have_prefixcli_tree)"
fi

# 1) provenance: the tree must still be at the pinned parent commit and the
#    upstream fix commit must not be reachable from this object store (an
#    agent that fetched or grafted the fix earns 0; the fix direction must
#    come from the agent's own work).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in. Content check against the pinned commit's own blobs, plus no
#    untracked non-ignored files (build/ is gitignored) - and the bug's file
#    must actually have changed from the pinned commit.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/parser/peg/transformer/transform_create_sequence.cpp) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            case "$mode" in
                120000*)  # symlink: git stores the link target string
                    have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                    ;;
                *)
                    have=$(git hash-object -- "$f" 2>/dev/null || true)
                    ;;
            esac
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
bf_want=$(git rev-parse "$PARENT:src/parser/peg/transformer/transform_create_sequence.cpp")
bf_have=$(git hash-object -- src/parser/peg/transformer/transform_create_sequence.cpp 2>/dev/null || true)
if [ "$bf_want" = "$bf_have" ]; then
    echo "bug's source file is byte-identical to the pinned commit (no fix)" >> "$LOG"; ok=0
else
    # the fix must live in the SOURCE itself: the delivered code must reject a
    # NULL option value with the descriptive Parser Error that the golden test
    # and the hidden cases assert. A wrapper around the binary or a source
    # change that merely differs cannot satisfy this.
    for msg in 'INCREMENT must not be NULL' 'MINVALUE must not be NULL' 'MAXVALUE must not be NULL' 'START value must not be NULL'; do
        grep -qF -- "$msg" src/parser/peg/transformer/transform_create_sequence.cpp || {
            echo "fix message not present in the bug's source file: $msg" >> "$LOG"; ok=0; }
    done
fi
if [ "$ok" != "1" ]; then
    tail -30 "$LOG" >&2
    fail "working tree scope or fix-content check failed (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
# the reproduction must cover all four NULL paths per the contract
for needle in 'START WITH NULL' 'START NULL' 'MINVALUE NULL' 'MAXVALUE NULL' 'INCREMENT BY NULL'; do
    grep -qF -- "$needle" /app/repro.sh || fail "repro.sh does not cover the required case: $needle"
done

# 4) rebuild the delivered tree from source with the project's own build (the
#    CLI and the unittest runner below then genuinely reflect the delivered
#    code; a source change that does not compile fails here).
[ -f build/release/build.ninja ] || fail "build/release/build.ninja is missing (build directory was deleted)"
if ! ninja -C build/release > /tmp/rebuild.log 2>&1; then
    tail -20 /tmp/rebuild.log
    fail "ninja rebuild of /app/src failed (see /tmp/rebuild.log)"
fi
[ -x build/release/duckdb ] || fail "build/release/duckdb is missing after rebuild"
[ -x build/release/test/unittest ] || fail "build/release/test/unittest is missing after rebuild"
# the executed binaries must be genuine ELF executables produced by the
# project's own build - not shell wrappers printing canned output.
elfmagic() { od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n'; }
if [ "$(elfmagic build/release/duckdb)" != "7f454c46" ]; then
    fail "build/release/duckdb is not an ELF executable"
fi
if [ "$(elfmagic build/release/test/unittest)" != "7f454c46" ]; then
    fail "build/release/test/unittest is not an ELF executable"
fi

# 5) the pre-fix tree concept: the pristine pre-fix CLI baked into the image
#    at build time (built from the parent tree BEFORE the agent existed).
#    DuckDB's unity build records absolute /app/src include paths, so a
#    copied/rebuilt tree would silently re-read the FIXED sources from
#    /app/src; the baked binary is the only faithful pre-fix build and is
#    sha256-pinned above (both /opt/prefix/bin/duckdb and its byte-copy at
#    /opt/prefix/tree/build/release/duckdb).
PREFIX_TREE=/opt/prefix/tree
[ -x "$PREFIX_TREE/build/release/duckdb" ] || fail "pre-fix tree CLI missing"


# 6) the agent's reproduction, both directions. Against the repaired tree it
#    must pass; against the pre-fix copy it must fail - any exit 0 there
#    means the reproduction is fake/hardcoded or the symptom is not what we
#    think it is.
if ! bash /app/repro.sh /app/src > /tmp/repro_fixed.out 2>&1; then
    cat /tmp/repro_fixed.out | head -30 >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if bash /app/repro.sh "$PREFIX_TREE" > /tmp/repro_prefix.out 2>&1; then
    cat /tmp/repro_prefix.out | head -30 >> "$LOG"
    fail "agent repro passed against the PRE-FIX tree (expected failure; see $LOG)"
fi

# 7) the upstream regression test: plant the golden bytes (fix-commit version
#    of test_sequence.test, extracted at image build time, sha256-pinned; never
#    part of this task tree) over the tree's copy, then run it with the
#    project's own runner. The golden file adds six NULL-option cases atop the
#    parent file (parent: 127 assertions), so a full pass must reach at least
#    133 assertions.
cp /opt/golden/test_sequence.test test/sql/catalog/sequence/test_sequence.test \
    || fail "cannot plant golden test_sequence.test"
golden_log=/tmp/golden_fixed.log
if ! ( cd /app/src && ./build/release/test/unittest test/sql/catalog/sequence/test_sequence.test > "$golden_log" 2>&1 ); then
    tail -20 "$golden_log" >&2
    fail "upstream regression test did not pass on the repaired tree (see $golden_log)"
fi
golden_asserts=$(sed -nE 's/^All tests passed \(([0-9]+) assertions.*/\1/p' "$golden_log" | head -1)
if [ -z "$golden_asserts" ] || [ "$golden_asserts" -lt 133 ]; then
    tail -10 "$golden_log" >&2
    fail "upstream regression test: expected >=133 passing assertions on the repaired tree, summary says '$golden_asserts' (see $golden_log)"
fi
echo "  golden: $golden_asserts assertions passed on the repaired tree" >> "$LOG"

# 8) the project's own existing suite for the affected subsystem: the whole
#    test/sql/catalog/sequence/ directory (includes the golden-planted file).
suite_log=/tmp/suite_fixed.log
if ! ( cd /app/src && ./build/release/test/unittest "test/sql/catalog/sequence/*" > "$suite_log" 2>&1 ); then
    tail -20 "$suite_log" >&2
    fail "sequence regression suite did not pass on the repaired tree (see $suite_log)"
fi
suite_cases=$(sed -nE 's/^All tests passed \([0-9]+ assertions in ([0-9]+) test cases.*/\1/p' "$suite_log" | head -1)
if [ -z "$suite_cases" ] || [ "$suite_cases" -lt 11 ]; then
    tail -10 "$suite_log" >&2
    fail "sequence regression suite: expected >=11 test files, summary says '$suite_cases' (see $suite_log)"
fi
echo "  suite: $suite_cases test files passed on the repaired tree" >> "$LOG"

# 9) hidden cases: authored inputs reaching the same parser path that the
#    upstream regression test does not use. Each case must PASS on the
#    repaired tree's CLI and FAIL on the pre-fix copy's CLI.
run_case() {  # $1 = cli  $2 = statement  $3 = expected substring ; prints PASS/FAIL
    # Text-based verdict; the CLI's exit code is not part of the contract:
    # what matters is that the statement is REJECTED with a clean Parser
    # Error naming the option, and never crashes with INTERNAL Error.
    cli=$1; stmt=$2; expect=$3
    out=$("$cli" -c "$stmt" 2>&1)
    if echo "$out" | grep -q "INTERNAL Error"; then
        echo "internal: $stmt" >> "$LOG"
        echo "$out" | head -3 >> "$LOG"
        echo "FAIL-internal"
        return 1
    fi
    if echo "$out" | grep -q "Parser Error" && echo "$out" | grep -qF "$expect"; then
        echo "PASS"
        return 0
    fi
    echo "mismatch: $stmt" >> "$LOG"
    echo "$out" | head -5 >> "$LOG"
    echo "FAIL-mismatch"
    return 1
}

CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    cf="$case/case.txt"
    [ -f "$cf" ] || fail "hidden case $name has no case.txt"
    IFS=$'\t' read -r stmt expect < "$cf" || true
    [ -n "$stmt" ] || fail "hidden case $name: empty statement"
    [ -n "$expect" ] || fail "hidden case $name: empty expectation"

    fixed_res=$(run_case /app/src/build/release/duckdb "$stmt" "$expect")
    if [ "$fixed_res" != "PASS" ]; then
        fail "hidden case $name did not pass on the repaired tree (result: $fixed_res; see $LOG)"
    fi

    prefix_res=$(run_case "$PREFIX_TREE/build/release/duckdb" "$stmt" "$expect")
    if [ "$prefix_res" = "PASS" ]; then
        fail "hidden case $name passed on the PRE-FIX tree (expected failure; see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 5 ] || fail "only $CASES hidden case(s) ran; expected 5"

echo "PASS: provenance, fix-unreachable, scope, deliverables, rebuild, repro both directions, golden regression test, sequence suite, and all hidden cases (both directions)"
echo 1 > /logs/verifier/reward.txt
exit 0