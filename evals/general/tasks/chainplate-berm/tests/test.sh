#!/bin/bash
# Verifier for chainplate-berm: proves the agent's fix in the real netty/netty
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit; every tracked file except the single JdkZlibDecompressor source file
# is byte-identical to it; no stray untracked files), (2) requiring
# /app/summary.md, (3) planting the upstream project's own regression test for
# this bug (extracted from the fix commit at image build time into /opt/golden)
# plus three authored hidden-case classes into the codec-compression test tree
# and running them together offline through the project's own Maven/surefire
# runner, and (4) running a selection of the project's own existing
# codec-compression tests to prove nothing else broke.
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

PARENT=87d2f7506cee4100d765be62c481dbd22c9501dc
ALLOWED=codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecompressor.java
TESTDIR=codec-compression/src/test/java/io/netty/handler/codec/compression

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the zlib decompressor implementation in codec-compression, discovered
#    by the agent, not named here). CONTENT check, not a git-status check: we
#    hash the actual bytes of every tracked file on disk against the pinned
#    commit's own blob, so assume-unchanged/skip-worktree tricks cannot hide a
#    dirty file, and we refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$ALLOWED") : ;;
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

# 2.5) the single allowed file must actually carry a fix, as real non-symlink
# source: it must differ in bytes from the pinned parent blob (the parent
# blob is the buggy code, so an unchanged file cannot be a fix), and it must
# not be a symlink (a link to an extracted file elsewhere would compile as
# fixed source while the tree holds no fix). The module output directory is
# then deleted so the graded test run MUST rebuild codec-compression from the
# on-disk source bytes: without this, precompiled fixed .class files (with
# mtimes aged so maven's incremental compiler skips the module) pass every
# test while the source stays buggy.
if [ -L "$ALLOWED" ]; then
    tail -30 "$LOG"
    fail "$ALLOWED is a symlink; the fix must be real source in a regular file"
fi
parent_blob=$(git rev-parse "$PARENT:$ALLOWED" 2>/dev/null || true)
have_blob=$(git hash-object -- "$ALLOWED" 2>/dev/null || true)
if [ -z "$parent_blob" ] || [ -z "$have_blob" ] || [ "$have_blob" = "$parent_blob" ]; then
    tail -30 "$LOG"
    fail "$ALLOWED is byte-identical to the pinned parent; no fix present"
fi
if ! rm -rf codec-compression/target; then
    fail "cannot remove codec-compression/target before the graded build"
fi
echo "allowed source changed (not a symlink); module target removed; graded build recompiles from source" >> "$LOG"

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) plant the golden upstream regression test and the authored hidden-case
#    classes into the codec-compression test tree.
GOLDEN=/opt/golden/JdkZlibDecompressorTest.java
[ -f "$GOLDEN" ] || fail "/opt/golden/JdkZlibDecompressorTest.java missing"
cp "$GOLDEN" "$TESTDIR/JdkZlibDecompressorTest.java" || fail "cannot plant golden regression test"
HIDDEN_LIST=""
HIDDEN_CLASSES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    for src in "$case"*Test.java; do
        [ -f "$src" ] || continue
        cp "$src" "$TESTDIR/$(basename "$src")" || fail "cannot plant hidden case $(basename "$src")"
        HIDDEN_LIST="${HIDDEN_LIST},"$(basename "$src" .java)
        HIDDEN_CLASSES=$((HIDDEN_CLASSES + 1))
    done
done
if [ "$HIDDEN_CLASSES" -lt 2 ]; then
    fail "only $HIDDEN_CLASSES hidden case(s) planted; expected at least 2"
fi

# 5) the module compiles from the agent's tree and the project's own test
#    runner passes the upstream regression test plus every hidden case in one
#    offline surefire run. The upstream class is parameterized over the ZLIB,
#    GZIP and NONE wrappers (12 tests x 3 = 36 runs); the three hidden classes
#    add 6 more, for 42 tests total. If any of them fails at the fixed tree,
#    the fix is incomplete.
if ! mvn -o -pl codec-compression test -Dtest="JdkZlibDecompressorTest${HIDDEN_LIST}" \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > "$LOG.mvn1" 2>&1; then
    tail -50 "$LOG.mvn1" >&2
    fail "golden regression test + hidden cases did not pass (see $LOG.mvn1)"
fi
if ! grep -q "Tests run: 42, Failures: 0, Errors: 0" "$LOG.mvn1"; then
    {
        echo "surefire summary did not match 'Tests run: 42, Failures: 0, Errors: 0':"
        grep -E "Tests run:" "$LOG.mvn1" | tail -5
    } >> "$LOG"
    fail "golden + hidden surefire summary mismatch (see $LOG)"
fi

# 6) a selection of the project's OWN existing codec-compression tests must
#    stay green (proves the fix broke nothing else in the module).
if ! mvn -o -pl codec-compression test \
        -Dtest=JdkZlibTest,ByteBufChecksumTest,DefensiveDecompressorTest,InputBufferingDecompressorTest \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > "$LOG.mvn2" 2>&1; then
    tail -50 "$LOG.mvn2" >&2
    fail "existing codec-compression test selection did not pass (see $LOG.mvn2)"
fi
if ! grep -qE "Tests run: [1-9][0-9]*, Failures: 0, Errors: 0" "$LOG.mvn2"; then
    {
        echo "existing-suite surefire summary shows failures or nothing ran:"
        grep -E "Tests run:" "$LOG.mvn2" | tail -5
    } >> "$LOG"
    fail "existing-suite surefire summary mismatch (see $LOG)"
fi

echo "PASS: provenance, /app/summary.md, module compile, golden regression test, 6 hidden cases, existing suite"
echo 1 > /logs/verifier/reward.txt
exit 0