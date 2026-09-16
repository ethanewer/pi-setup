#!/bin/bash
# Verifier for mizzen-summit: proves the agent's change to the real
# apache/kafka 4.3.1 tree (bounded-capacity event accumulator) by running the
# module's own targeted test class plus two authored hidden test classes
# through Kafka's own Gradle+JUnit machinery, offline. Also enforces that no
# source outside the owning module changed, and that /app/summary.md exists.
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

PIN=26b251a451ce941d3d7a55e6487bcb7f16b5ad48
MOD=coordinator-common
PINNED_HEAD=$(cd /app/src && git rev-parse HEAD 2>/dev/null || true)

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned upstream commit (no commits added
#    by the agent could hide work from the diff scoping check).
if [ "$PINNED_HEAD" != "$PIN" ]; then
    fail "HEAD is $PINNED_HEAD, expected pinned $PIN"
fi

# 2) scope: every source change must live inside the owning module's src
#    tree (no build.gradle / settings.gradle / other-module / test-tree
#    changes). This is a CONTENT check, not a git-status check: git's
#    assume-unchanged / skip-worktree bits can hide a dirty build file from
#    `git diff`/`git status`, so we hash the actual bytes of every tracked
#    file outside $MOD/src against the pinned commit's blob.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$MOD"/src/*) : ;;
        *)
            want=$(git rev-parse "HEAD:$f" 2>/dev/null || true)
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-module changed/deleted file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    case "$f" in
        "$MOD"/src/*) : ;;
        *) echo "out-of-module untracked file: $f" >> "$LOG"; ok=0 ;;
    esac
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "source changes outside $MOD/src/ (see $LOG)"
fi

# 2b) gradle user-home guard: the verifier runs gradle with
#    GRADLE_USER_HOME=/app/.gradle-home (baked, warm cache). Gradle auto-loads
#    *.gradle from $GRADLE_USER_HOME/init.d and build plugins from
#    $GRADLE_USER_HOME/plugins; a planted script there could neutralise the
#    test task and skip every assertion. Refuse those auto-load locations
#    (top-level only), plus stray script files outside the baked distribution
#    (wrapper/dists) and dependency cache trees.
for d in init.d plugins; do
    if [ -e "/app/.gradle-home/$d" ]; then
        fail "injected $d/ found under /app/.gradle-home"
    fi
done
if [ -n "$(find /app/.gradle-home -path '*/wrapper/dists/*' -prune -o -path '*/caches/*' -prune -o -type f -name '*.gradle' -print -quit)" ]; then
    fail "stray gradle script file found under /app/.gradle-home"
fi

# 3) deliverable: the agent's own change summary must exist.
[ -f /app/summary.md ] || fail "/app/summary.md is missing"
[ -s /app/summary.md ] || fail "/app/summary.md is empty"

# 4) plant the two hidden test classes into the module's test source set.
HID=coordinator-common/src/test/java/org/apache/kafka/coordinator/common/runtime
cp /tests/hidden/capacity-bound/EventAccumulatorCapacityTest.java "$HID/" || fail "cannot plant hidden case 1"
cp /tests/hidden/per-key-reclaim/EventAccumulatorReclaimTest.java "$HID/" || fail "cannot plant hidden case 2"

# 5) run the module's own targeted test class + the two hidden classes in
#    ONE offline Gradle invocation (kafka's own JUnit setup).
export HOME=/app GRADLE_USER_HOME=/app/.gradle-home
./gradlew :coordinator-common:test \
  --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorTest \
  --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorCapacityTest \
  --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorReclaimTest \
  --offline > "$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ] || ! grep -q "BUILD SUCCESSFUL" "$LOG"; then
    echo "gradle run failed (exit $rc)" >> "$LOG"
    tail -50 "$LOG" >&2
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

# 6) the tests must actually have RUN: grep the gradle log for the per-test
#    result lines of all three classes. A skipped/neutralised run (init
#    script, exclude filter, failIfNoTests tricks) leaves no such lines even
#    though the build reports SUCCESSFUL, so this belt makes every test-skip
#    sabotage fail closed.
for cls in EventAccumulatorTest EventAccumulatorCapacityTest EventAccumulatorReclaimTest; do
    if ! grep -q "${cls} >" "$LOG"; then
        fail "gradle log shows no executed tests for $cls -- tests were skipped or did not run"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0