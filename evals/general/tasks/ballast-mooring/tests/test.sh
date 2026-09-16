#!/bin/bash
# Verifier for ballast-mooring: proves the agent's fix in the real
# netty/netty tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit; every tracked file except the single DateFormatter
# source file is byte-identical to it; no stray untracked files), (2)
# requiring /app/summary.md, (3) planting the upstream project's own
# regression test for this bug (extracted from the fix commit at image build
# time into /opt/golden) plus four authored hidden-case classes into the
# codec-base test tree and running them together offline through the
# project's own Maven/surefire runner, and (4) running a selection of the
# project's own existing codec-base tests to prove nothing else broke.
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

# 0) toolchain tripwire: the image recorded the hashes of mvn/git/javac/java at
#    build time; if any binary was swapped in the trial container (e.g. a fake
#    `mvn` that always reports green), everything below is meaningless, so we
#    refuse to score.
if ! { PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin sh -c '{ sha256sum -b $(command -v mvn) $(command -v git) $(command -v javac) $(command -v java); } | sort'; } | diff -q - /opt/toolchain.sha256 >/dev/null 2>&1; then
    fail "toolchain binaries differ from image build-time hashes (/opt/toolchain.sha256)"
fi

PARENT=ba8e9e64f89fc91b5085cd8bc21bd9ef83264ba1
TARGETDIR=codec-base/src/test/java/io/netty/handler/codec

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the HTTP-date token scanner in codec-base, discovered by the agent,
#    not named here). This is a CONTENT check, not a git-status check: we
#    hash the actual bytes of every tracked file on disk against the pinned
#    commit's own blob, so assume-unchanged/skip-worktree tricks cannot hide a
#    dirty file, and we refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        codec-base/src/main/java/io/netty/handler/codec/DateFormatter.java) : ;;
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

# 3) MECHANISM check, not just behaviour: the fix must live in the scanner's
#    trailing-token finalisation - the final token of a substring parse must be
#    bounded by the requested parse range `end`, and the old overrun
#    (finalising it with txt.length()) must be GONE. This is what blocks
#    input-trimming wrappers and hardcoded answers that leave the overrun bug
#    in place (verified: an input-trimming wrapper passes every behavioural
#    test yet never touches the bug; this check rejects it, the honest oracle
#    passes it).
DFM=codec-base/src/main/java/io/netty/handler/codec/DateFormatter.java
if [ ! -f "$DFM" ]; then
    fail "$DFM is missing"
fi
if grep -qE 'parseToken\(\s*txt\s*,\s*tokenStart\s*,\s*txt\.length\(\)\s*\)' "$DFM"; then
    fail "buggy trailing-token finalisation (parseToken(txt, tokenStart, txt.length())) is still present"
fi
if ! grep -qE 'parseToken\(\s*txt\s*,\s*tokenStart\s*,\s*end\s*\)' "$DFM"; then
    fail "trailing token is not finalised at the parse range end (parseToken(txt, tokenStart, end) missing)"
fi

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5) plant the golden upstream regression test and the authored hidden-case
#    classes into the codec-base test tree.
GOLDEN=/opt/golden/DateFormatterTest.java
[ -f "$GOLDEN" ] || fail "/opt/golden/DateFormatterTest.java missing"
cp "$GOLDEN" "$TARGETDIR/DateFormatterTest.java" || fail "cannot plant golden regression test"
HIDDEN_LIST=""
HIDDEN_CLASSES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    for src in "$case"*Test.java; do
        [ -f "$src" ] || continue
        cp "$src" "$TARGETDIR/$(basename "$src")" || fail "cannot plant hidden case $(basename "$src")"
        HIDDEN_LIST="${HIDDEN_LIST},"$(basename "$src" .java)
        HIDDEN_CLASSES=$((HIDDEN_CLASSES + 1))
    done
done
if [ "$HIDDEN_CLASSES" -lt 2 ]; then
    fail "only $HIDDEN_CLASSES hidden case(s) planted; expected at least 2"
fi

# 6) the module recompiles from the agent's tree and the project's own test
#    runner passes the upstream regression test plus every hidden case in one
#    offline surefire run: 14 upstream tests + 8 authored hidden tests = 22.
if ! mvn -o -pl codec-base test -Dtest="DateFormatterTest${HIDDEN_LIST}" \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > "$LOG.mvn1" 2>&1; then
    tail -50 "$LOG.mvn1" >&2
    fail "golden regression test + hidden cases did not pass (see $LOG.mvn1)"
fi
if ! grep -q "Tests run: 22, Failures: 0" "$LOG.mvn1"; then
    {
        echo "surefire summary did not match 'Tests run: 22, Failures: 0':"
        grep -E "Tests run:" "$LOG.mvn1" | tail -5
    } >> "$LOG"
    fail "golden + hidden surefire summary mismatch (see $LOG)"
fi

# 7) a selection of the project's OWN existing codec-base tests must stay
#    green (proves the fix broke nothing else in the module).
if ! mvn -o -pl codec-base test \
        -Dtest=Base64Test,JsonObjectDecoderTest,LineEncoderTest,StringDecoderTest,ByteArrayDecoderTest \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > "$LOG.mvn2" 2>&1; then
    tail -50 "$LOG.mvn2" >&2
    fail "existing codec-base test selection did not pass (see $LOG.mvn2)"
fi
if ! grep -qE "Tests run: [1-9][0-9]*, Failures: 0, Errors: 0" "$LOG.mvn2"; then
    {
        echo "existing-suite surefire summary shows failures or nothing ran:"
        grep -E "Tests run:" "$LOG.mvn2" | tail -5
    } >> "$LOG"
    fail "existing-suite surefire summary mismatch (see $LOG)"
fi

echo "PASS: provenance, /app/summary.md, module compile, golden regression test, 8 hidden cases, existing suite"
echo 1 > /logs/verifier/reward.txt
exit 0