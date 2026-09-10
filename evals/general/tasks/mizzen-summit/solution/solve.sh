#!/bin/bash
# Oracle for mizzen-summit: implements the bounded-capacity feature in the
# real apache/kafka tree at /app/src (only the event accumulator class in the
# owning module), writes the required /app/summary.md, and proves the module's
# own targeted test class still passes, offline. Reads only /app and /solution,
# never /tests.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/feature.patch || {
    echo "oracle: feature.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/feature.patch
echo "oracle: applied bounded-capacity feature patch"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Implemented an optional bounded capacity on the coordinator runtime's shared
event accumulator.

Class modified: `org.apache.kafka.coordinator.common.runtime.EventAccumulator`
(in Kafka's `coordinator-common` module).

Semantics: a new `EventAccumulator(int maxSize)` (and a
`EventAccumulator(Random, int maxSize)`) constructor bounds the number of
queued events. `addLast`/`addFirst` throw
`java.util.concurrent.RejectedExecutionException` as soon as the accumulator
holds `maxSize` events, leaving contents and `size()` untouched; `poll()`
frees a slot immediately; `done()` does not change the count. Non-positive
capacities are rejected at construction with `IllegalArgumentException`, and
the no-argument constructor remains unbounded.

Verification: the module's existing `EventAccumulatorTest` class run via
`./gradlew :coordinator-common:test --tests
org.apache.kafka.coordinator.common.runtime.EventAccumulatorTest --offline`.
MD

export HOME=/app GRADLE_USER_HOME=/app/.gradle-home
./gradlew :coordinator-common:test \
  --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorTest \
  --offline > /tmp/oracle_gradle.log 2>&1
rc=$?
if [ "$rc" -ne 0 ] || ! grep -q "BUILD SUCCESSFUL" /tmp/oracle_gradle.log; then
    echo "oracle: targeted test class did not pass (exit $rc); tail:" >&2
    tail -30 /tmp/oracle_gradle.log >&2
    exit 1
fi

echo "oracle: feature implemented, summary written, targeted tests green"
exit 0