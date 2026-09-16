#!/bin/bash
# Verifier for kelson-current: proves the agent's fix in the real
# netty/netty tree at /app/src (codec-compression module) by (1) asserting
# the verifier's own trust anchors (golden test, pristine pre-fix decoder
# source and toolchain binaries still have the sha256 pinned at image build
# time), (2) asserting provenance (HEAD still the pinned parent commit;
# every tracked file except the bug's source file byte-identical to it; new
# untracked files allowed only in the module's test package), (3) requiring
# /app/repro.sh and /app/summary.md, (4) deleting the module's compiled
# target/ and running the agent's own reproduction against the repaired
# tree (must pass with a real surefire summary), (5) planting the upstream
# project's own regression test (extracted from the fix commit at image
# build time into /opt/golden, sha256-pinned) plus three authored hidden
# cases and running them together with the module's pre-existing
# gzip/zlib tests (must pass), and (6) running the agent's reproduction
# against the pristine PRE-FIX decoder source (baked at /opt/prefix) where
# it must FAIL - proving the symptom is real and the reproduction targets
# it.
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

PARENT=6dabf563b6acdc30448f2b09685fbdcd5d88e39a
GIT=/usr/bin/git
export MAVEN_OPTS="-Xmx4g -Dmaven.wagon.http.pool=false"
DECODER=codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java
TESTPKGDIR=codec-compression/src/test/java/io/netty/handler/codec/compression
GOLDEN_TESTS="JdkZlibTest HiddenFextraCaseLargeExtra HiddenFextraCaseWideZeroLow HiddenFextraCaseConcatMixed"
MVNFLAGS="-o -pl codec-compression test -Dsurefire.failIfNoSpecifiedTests=true -Dcheckstyle.skip=true -Dxml.format.skip=true -Dlicense.skip=true"

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test and
#    the pre-fix decoder source; an adversarial agent (e.g. a root trial)
#    could otherwise swap the toolchain for stubs, replace /opt/prefix so
#    the pre-fix direction check fails to fail, or tamper with the golden
#    test, and earn reward 1 on an untouched tree. The pins recorded at
#    image build time detect any substitution before anything is executed.
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/prefix.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ); then
    fail "toolchain, golden or prefix integrity check failed (substituted file)"
fi

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide from the blob-level scope check below.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (the gzip header parser in codec-compression, discovered by
#    the agent, not named here). This is a CONTENT check, not a
#    git-status check: we hash the actual bytes of every tracked file on
#    disk against the pinned commit's own blob. New files are allowed only
#    in the module test package, where the agent's reproduction test must
#    live; anything else, tracked or untracked, fails.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <("$GIT" ls-files -z)
while IFS= read -r -d '' f; do
    case "$f" in
        codec-compression/src/test/java/io/netty/handler/codec/compression/*) : ;;
        *)
            echo "untracked non-ignored file outside the module test package: $f" >> "$LOG"; ok=0
            ;;
    esac
done < <("$GIT" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -x /app/repro.sh ] || fail "/app/repro.sh is missing or not executable"
[ -s /app/repro.sh ] || fail "/app/repro.sh is empty"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) delete the module's compiled output: the tree must COMPILE from the
#    agent's sources; anything an agent planted under the git-ignored
#    target/ dir cannot survive this.
rm -rf codec-compression/target

# 5) the agent's reproduction against the REPAIRED tree must pass AND must
#    show a real surefire summary (exit code alone is not enough: a wrapper
#    that always exits 0 would otherwise pass).
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro exited nonzero on the repaired tree; tail of output:" >> "$LOG"
    tail -15 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro failed on the repaired tree (see $LOG)"
fi
perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' /tmp/repro_fixed.out > /tmp/repro_fixed.plain
line=$(grep -oE 'Tests run: [0-9]+[,] Failures: [0-9]+[,] Errors: [0-9]+[,] Skipped: [0-9]+' /tmp/repro_fixed.plain | tail -1)
if [ -z "$line" ]; then
    tail -15 /tmp/repro_fixed.out >> "$LOG"
    fail "repaired-tree repro shows no surefire test summary (wrapped call? see $LOG)"
fi
n=$(printf '%s' "$line" | sed -E 's/.*Tests run: ([0-9]+).*/\1/')
f=$(printf '%s' "$line" | sed -E 's/.*Failures: ([0-9]+).*/\1/')
e=$(printf '%s' "$line" | sed -E 's/.*Errors: ([0-9]+).*/\1/')
if [ "$n" -lt 1 ] || [ "$f" -ne 0 ] || [ "$e" -ne 0 ]; then
    fail "repaired-tree repro did not run one passing test (summary: $line)"
fi

# 6) plant the project's OWN regression test for this bug (golden bytes,
#    extracted from the fix commit at image build time and sha256-pinned;
#    never part of this task tree) and the three authored hidden cases,
#    then run everything together with the module's pre-existing
#    gzip/zlib tests. The golden JdkZlibTest file contains all the
#    pre-existing tests plus the two regression tests upstream added, so a
#    pass here also proves the existing suite.
cp /opt/golden/JdkZlibTest.java "$TESTPKGDIR/JdkZlibTest.java" || fail "cannot plant golden regression test"
cp /tests/hidden/case_large_extra/HiddenFextraCaseLargeExtra.java "$TESTPKGDIR/" || fail "cannot plant hidden case large_extra"
cp /tests/hidden/case_wide_zero_low/HiddenFextraCaseWideZeroLow.java "$TESTPKGDIR/" || fail "cannot plant hidden case wide_zero_low"
cp /tests/hidden/case_concat_mixed/HiddenFextraCaseConcatMixed.java "$TESTPKGDIR/" || fail "cannot plant hidden case concat_mixed"

if ! mvn $MVNFLAGS -Dtest=JdkZlibTest,HiddenFextraCaseLargeExtra,HiddenFextraCaseWideZeroLow,HiddenFextraCaseConcatMixed > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >> "$LOG"
    fail "golden regression test + hidden cases failed on the repaired tree (see $LOG)"
fi
perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' /tmp/golden.out > /tmp/golden.plain
line=$(grep -oE 'Tests run: [0-9]+[,] Failures: [0-9]+[,] Errors: [0-9]+[,] Skipped: [0-9]+' /tmp/golden.plain | tail -1)
n=$(printf '%s' "$line" | sed -E 's/.*Tests run: ([0-9]+).*/\1/')
f=$(printf '%s' "$line" | sed -E 's/.*Failures: ([0-9]+).*/\1/')
e=$(printf '%s' "$line" | sed -E 's/.*Errors: ([0-9]+).*/\1/')
if [ "$n" -lt 27 ] || [ "$f" -ne 0 ] || [ "$e" -ne 0 ]; then
    echo "golden+hidden run summary: $line" >> "$LOG"
    tail -30 /tmp/golden.out >> "$LOG"
    fail "golden+hidden run did not execute all tests cleanly (expected >= 27, got $n; see $LOG)"
fi
for cls in $GOLDEN_TESTS; do
    grep -qE "in io\.netty\.handler\.codec\.compression\.${cls}[[:space:]]*$" /tmp/golden.plain || {
        echo "no per-class summary for ${cls} in golden+hidden run" >> "$LOG"
        tail -30 /tmp/golden.plain >> "$LOG"
        fail "class ${cls} did not run and pass (see $LOG)"
    }
done

# 7) the agent's reproduction against the pristine PRE-FIX state: swap the
#    original buggy decoder source (baked at /opt/prefix, sha256-pinned)
#    into a scratch tree compiled from the agent's sources and require the
#    reproduction to FAIL there. Exit-0-without-failing-test-evidence is a
#    fake/wrapped reproduction and fails this step.
cp "$DECODER" /tmp/agent-decoder.java || fail "cannot snapshot agent's decoder source"
cp /opt/prefix/JdkZlibDecoder.java "$DECODER" || fail "cannot plant pristine pre-fix decoder source"
find codec-compression/target -name 'JdkZlibDecoder*.class' -delete 2>/dev/null || true
touch "$DECODER"
if bash /app/repro.sh > /tmp/repro_prefix.out 2>&1; then
    perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' /tmp/repro_prefix.out > /tmp/repro_prefix.plain
    line=$(grep -oE 'Tests run: [0-9]+[,] Failures: [0-9]+[,] Errors: [0-9]+[,] Skipped: [0-9]+' /tmp/repro_prefix.plain | tail -1)
    if [ -z "$line" ]; then
        cp /tmp/agent-decoder.java "$DECODER"
        echo "agent repro exited 0 on the pre-fix tree with no failing test summary:" >> "$LOG"
        tail -8 /tmp/repro_prefix.out >> "$LOG"
        fail "agent repro did not fail on the pre-fix tree (wrapped call? see $LOG)"
    fi
    n=$(printf '%s' "$line" | sed -E 's/.*Tests run: ([0-9]+).*/\1/')
    f=$(printf '%s' "$line" | sed -E 's/.*Failures: ([0-9]+).*/\1/')
    e=$(printf '%s' "$line" | sed -E 's/.*Errors: ([0-9]+).*/\1/')
    if [ "$n" -ge 1 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ]; then
        cp /tmp/agent-decoder.java "$DECODER"
        fail "agent repro PASSED against the pre-fix tree (reproduction is fake or does not target the bug)"
    fi
    # exit 0 with failing test evidence also counts as the required failure
else
    : # nonzero exit from the reproduction = evidence it failed as required
fi
cp /tmp/agent-decoder.java "$DECODER" || fail "cannot restore agent's decoder source"

echo "PASS: trust anchors, provenance/scope, deliverables, module rebuild, repro both directions, golden regression test + existing gzip/zlib tests, hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0