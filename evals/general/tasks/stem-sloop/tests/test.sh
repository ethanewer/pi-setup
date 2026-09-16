#!/bin/bash
# Verifier for stem-sloop: proves the agent's fix in the real google/guava
# tree at /app/src by (1) asserting the verifier's own trust anchors (the
# upstream regression-test files and the pristine pre-fix classes still have
# the sha256 pins recorded at image build time), (2) asserting provenance
# (HEAD still the pinned parent commit; the upstream fix commit is not
# reachable from this clone), (3) requiring the working tree to be
# byte-identical to the pinned commit except for the graph-package source
# files the bug lives in (and no stray untracked files), (4) requiring
# /app/repro.sh and /app/summary.md, (5) compiling guava/src, guava-testlib
# and the graph test directory freshly from the delivered tree (so nothing
# planted under any compile output can survive and the executed classes are
# provably built from the agent's sources; the project's own regression
# tests for this bug, extracted from the fix commit at image build time, are
# planted over the tree's test copies first), (6) running the agent's own
# reproduction against the fresh compile (must pass), against a pristine
# pre-fix compile baked at /opt/prefix/classes (must fail - proving the
# symptom is real and the reproduction targets it) and with its default
# self-compile path (must pass), (7) running the seven upstream regression
# test methods by name with an authored RunOne JUnit helper, (8) running the
# project's own existing graph JUnit suite (21 classes) whole, and (9)
# running three authored hidden cases that reach the same code path from
# inputs the upstream tests do not use.
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

PARENT=7731825df8008c3fa65096d2681952eddd3b0c2d
FIX=76260d9b3c6acbabf9a8ddae11d4fff3985b6272

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the golden tests, the pre-fix
#    classes, the jars, the RunOne helper and (via javac/java) the
#    toolchain; an adversarial non-root agent with write access to /opt
#    could otherwise substitute any of them. The pins recorded at image
#    build time detect substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! (cd /opt/prefix/classes && sha256sum -c /opt/pins/prefix-classes.sha256 >/dev/null 2>&1) || \
   ! (cd /opt/prefix/testlib && sha256sum -c /opt/pins/prefix-testlib.sha256 >/dev/null 2>&1) || \
   ! sha256sum -c /opt/pins/jars.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix classes, jars, run helper or toolchain integrity check failed (substituted file)"
fi
[ -r /opt/golden/EndpointPairTest.java ] || fail "golden EndpointPairTest missing"
[ -r /opt/golden/ValueGraphTest.java ] || fail "golden ValueGraphTest missing"

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

# 2) scope: every change must live in exactly the graph-package source
#    files the bug lives in (discovered by the agent, not named here). This
#    is a CONTENT check, not a git-status check: the actual bytes of every
#    tracked file on disk are hashed against the pinned commit's own blob,
#    so assume-unchanged / skip-worktree tricks cannot hide a dirty file,
#    and any untracked file - ignored by .gitignore or not - is refused
#    (the instruction promises any stray file inside /app/src is flagged;
#    a pristine checkout carries no untracked files at all). The android/
#    mirror copies of the three files are also left free (they are not
#    compiled by anything graded, but a thorough agent may update them in
#    step).
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        guava/src/com/google/common/graph/AbstractBaseGraph.java| \
        guava/src/com/google/common/graph/AbstractNetwork.java| \
        guava/src/com/google/common/graph/GraphConstants.java| \
        android/guava/src/com/google/common/graph/AbstractBaseGraph.java| \
        android/guava/src/com/google/common/graph/AbstractNetwork.java| \
        android/guava/src/com/google/common/graph/GraphConstants.java)
            : ;;  # the files the bug lives in
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
            is_gitlink=0
            case "$mode" in 160000*) is_gitlink=1 ;; esac
            if [ "$is_gitlink" -eq 0 ]; then
                case "$mode" in
                    120000*)
                        have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                        ;;
                    *)
                        have=$(git hash-object -- "$f" 2>/dev/null || true)
                        ;;
                esac
                if [ -z "$have" ] || [ "$have" != "$want" ]; then
                    echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
                fi
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked file in tree: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z)
# the fix must actually touch the graph-ordering source (at least one of
# the three main source files must differ from the parent blobs)
p1=$(git rev-parse "$PARENT:guava/src/com/google/common/graph/AbstractBaseGraph.java")
p2=$(git rev-parse "$PARENT:guava/src/com/google/common/graph/AbstractNetwork.java")
p3=$(git rev-parse "$PARENT:guava/src/com/google/common/graph/GraphConstants.java")
h1=$(git hash-object guava/src/com/google/common/graph/AbstractBaseGraph.java 2>/dev/null || true)
h2=$(git hash-object guava/src/com/google/common/graph/AbstractNetwork.java 2>/dev/null || true)
h3=$(git hash-object guava/src/com/google/common/graph/GraphConstants.java 2>/dev/null || true)
if [ "$h1" = "$p1" ] && [ "$h2" = "$p2" ] && [ "$h3" = "$p3" ]; then
    echo "no change in the graph-ordering source files" >> "$LOG"; ok=0
fi
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source files (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
head -1 /app/repro.sh | grep -q '^#!/bin/bash' || fail "/app/repro.sh must be a bash script"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
if grep -qF '/opt/prefix' /app/repro.sh; then
    fail "/app/repro.sh must not special-case grader infrastructure"
fi

# 4) fresh compile of the delivered tree. Everything the verifier is about
#    to execute is compiled here, so the classes come from the tree as
#    delivered; a planted prebuilt class cannot survive, and a tree that
#    does not compile fails here.
rm -rf /tmp/v && mkdir -p /tmp/v/classes /tmp/v/testlib /tmp/v/gtests
if ! javac -d /tmp/v/classes -cp "/opt/jars/*" \
      $(find /app/src/guava/src -name '*.java' | sort) > "$LOG.javac" 2>&1; then
    tail -20 "$LOG.javac" >&2
    fail "javac of guava/src failed on the agent's tree (see $LOG.javac)"
fi
[ -s /tmp/v/classes/com/google/common/graph/AbstractBaseGraph.class ] \
    || fail "guava/src compile did not produce graph classes"
if ! javac -d /tmp/v/testlib -cp "/opt/jars/*:/tmp/v/classes" \
      $(find /app/src/guava-testlib/src -name '*.java' | sort) > "$LOG.testlib" 2>&1; then
    tail -20 "$LOG.testlib" >&2
    fail "javac of guava-testlib failed (see $LOG.testlib)"
fi

# 5) plant the project's own regression tests (golden bytes, extracted from
#    the fix commit at image build time and sha256-pinned; never part of
#    this task tree) over the tree's test copies, then compile the graph
#    test directory.
cp /opt/golden/EndpointPairTest.java \
   /opt/golden/ValueGraphTest.java \
   /opt/golden/AbstractStandardUndirectedGraphTest.java \
   /opt/golden/AbstractStandardUndirectedNetworkTest.java \
   /app/src/guava-tests/test/com/google/common/graph/ \
    || fail "cannot plant golden tests"
if ! javac -d /tmp/v/gtests -cp "/opt/jars/*:/tmp/v/classes:/tmp/v/testlib" \
      $(find /app/src/guava-tests/test/com/google/common/graph -name '*.java' | grep -v PackageSanityTests | sort) \
      > "$LOG.gtests" 2>&1; then
    tail -20 "$LOG.gtests" >&2
    fail "javac of the graph test directory failed (see $LOG.gtests)"
fi

# 6) the agent's reproduction, three ways. The repro's declared contract is
#    the EXIT CODE (exit 0 iff the Collection contract holds, non-zero
#    otherwise) plus printing both booleans and a verdict line; the verdict
#    wording is the agent's own, so no literal string is demanded here. On
#    the fresh compile of the repaired tree it must pass; against the
#    pristine pre-fix classes baked into the image it must fail (any exit 0
#    there means the reproduction is fake/hardcoded or the symptom is not
#    what we think it is); with its own default compile path it must pass
#    too. A driver that never ran (no stdout) cannot evidence either
#    direction, so both runs must produce output.
if ! CLASSES_DIR=/tmp/v/classes bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
[ -s /tmp/repro_fixed.out ] \
    || fail "agent repro on the repaired tree produced no output; the driver must print both booleans and a verdict line"
CLASSES_DIR=/opt/prefix/classes bash /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX classes (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
[ -s /tmp/repro_prefix.out ] \
    || fail "agent repro on pre-fix classes exited nonzero with no output; a driver that never ran its checks cannot evidence the violation"
if ! bash /app/repro.sh > /tmp/repro_default.out 2>&1; then
    echo "agent repro failed via its own default compile path; stdout:" >> "$LOG"
    head -10 /tmp/repro_default.out >> "$LOG"
    fail "agent repro exited nonzero with CLASSES_DIR unset (see $LOG)"
fi

# 7) the upstream regression test methods, by name (presence-proof: each
#    method must actually execute and pass, not merely be compiled).
CP="/opt/run:/opt/jars/*:/tmp/v/classes:/tmp/v/testlib:/tmp/v/gtests"
GOLDEN_METHODS="
EndpointPairTest endpointPair_undirected_contains
ValueGraphTest hasEdgeConnecting_undirected_mismatch
ValueGraphTest edgeValueOrDefault_undirected_mismatch
ValueGraphTest putEdgeValue_undirected_orderMismatch
StandardMutableUndirectedGraphTest hasEdgeConnecting_mismatch
StandardMutableUndirectedNetworkTest edgesConnecting_orderMismatch
StandardMutableUndirectedNetworkTest edgeConnectingOrNull_orderMismatch
"
while read -r cls mth; do
    [ -n "$cls" ] || continue
    if ! java -cp "$CP" RunOne "com.google.common.graph.$cls" "$mth" > /tmp/runone.out 2>&1; then
        echo "golden method $cls#$mth failed; output:" >> "$LOG"
        tail -15 /tmp/runone.out >> "$LOG"
        fail "upstream regression method $cls#$mth did not pass (see $LOG)"
    fi
    grep -q "failures=0" /tmp/runone.out \
        || { tail -5 /tmp/runone.out >> "$LOG"; fail "RunOne reported an unexpected outcome for $cls#$mth (see $LOG)"; }
done <<< "$GOLDEN_METHODS"

# 8) the project's own existing graph suite, whole classes. The scope check
#    above guarantees every file except the allowed source files is
#    byte-identical to the pinned commit, so a green run proves the fix
#    broke nothing else.
SUITE_CLASSES="
com.google.common.graph.EndpointPairTest
com.google.common.graph.ValueGraphTest
com.google.common.graph.GraphEquivalenceTest
com.google.common.graph.NetworkEquivalenceTest
com.google.common.graph.GraphsTest
com.google.common.graph.GraphPropertiesTest
com.google.common.graph.GraphMutationTest
com.google.common.graph.NetworkMutationTest
com.google.common.graph.ElementOrderTest
com.google.common.graph.MapCacheTest
com.google.common.graph.TraverserTest
com.google.common.graph.StandardMutableUndirectedGraphTest
com.google.common.graph.StandardMutableDirectedGraphTest
com.google.common.graph.StandardMutableUndirectedNetworkTest
com.google.common.graph.StandardMutableDirectedNetworkTest
com.google.common.graph.StandardImmutableUndirectedGraphTest
com.google.common.graph.StandardImmutableDirectedGraphTest
com.google.common.graph.ImmutableNetworkTest
com.google.common.graph.ImmutableValueGraphTest
com.google.common.graph.StandardImmutableGraphAdditionalTest
com.google.common.graph.DefaultNetworkImplementationsTest
"
# shellcheck disable=SC2086
if ! java -cp "$CP" org.junit.runner.JUnitCore $SUITE_CLASSES > /tmp/suite.out 2>&1; then
    tail -30 /tmp/suite.out >&2
    echo "project graph suite failed; tail:" >> "$LOG"
    tail -30 /tmp/suite.out >> "$LOG"
    fail "the project's own graph JUnit suite did not pass (see $LOG)"
fi
grep -qE "^OK \(" /tmp/suite.out || fail "graph suite did not report OK"

# 9) three authored hidden cases reaching the same code path from inputs
#    the upstream tests do not use: a string-node ValueGraph with values, a
#    Network with explicit edge objects, and an ImmutableGraph plus a
#    directed-graph regression check. Each is compiled against the fresh
#    compile of the agent's tree and must pass.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"*.java "$work"/ || fail "hidden case $name: no java sources"
    mainclass=$(basename "$(ls "$work"/*.java | head -1)" .java)
    if ! javac -cp /tmp/v/classes -d "$work" "$work"/*.java > "$work/javac.log" 2>&1; then
        tail -10 "$work/javac.log" >> "$LOG"
        fail "hidden case $name: javac failed (see $LOG)"
    fi
    ( cd "$work" && timeout 90 java -cp "$work:/tmp/v/classes" "$mainclass" > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stdout:" >> "$LOG"
        head -10 "$work/stdout.txt" >> "$LOG"
        head -10 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    marker="OK"
    case "$name" in
        h1-value-graph) marker="H1 OK" ;;
        h2-network) marker="H2 OK" ;;
        h3-immutable) marker="H3 OK" ;;
    esac
    grep -qF "$marker" "$work/stdout.txt" \
        || { tail -5 "$work/stdout.txt" >> "$LOG"; fail "hidden case $name: missing expected verdict $marker (see $LOG)"; }
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, fix-unreachable, scope, deliverables, fresh compile, repro (fixed/pre-fix/default), 7 upstream regression methods, project graph suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0