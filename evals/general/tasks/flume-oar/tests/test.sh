#!/bin/bash
# Verifier for flume-oar (executes-deliverable, hidden-case generalization).
#
# Grading has three phases, each of which must pass:
#
#  1. Fixture integrity: the serialized reference implementation shipped
#     in the image (lib/serial/serial.go) must be byte-identical to the
#     pristine file, and the visible test sources must be untouched.
#     They are the measurement baseline; tampering with them is a fail.
#
#  2. Race & correctness gate: the three hidden test cases plus the
#     visible test suite are compiled and run five times under the data
#     race detector:
#         go test -vet=off -race -count=5 ./...
#     The run must succeed AND emit zero "WARNING: DATA RACE" reports.
#     A cache whose Get touches shared slots without synchronization
#     fails this gate with race reports.
#
#  3. Throughput floor: an independent benchmark program (owned by this
#     verifier, compiled in at grade time) times the delivered cache
#     against the serialized reference on an identical disjoint-key
#     workload with 2ms per miss. The printed flume_ratio (serial /
#     parallel wall time) must be at least 2.5: a fix that serializes
#     the whole hot path scores ~1.0 and fails; a fix that keeps
#     unrelated misses overlapping scores ~8.
#
# Write reward.txt = 1 exactly when all three phases pass, else 0.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

FLOOR=2.5
failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

echo "=== flume-oar verifier ==="

# ---- toolchain ----
if ! command -v go >/dev/null 2>&1; then
    fail "go toolchain not on PATH"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
export HOME="${HOME:-/root}"
gopath="$HOME/go"
mkdir -p "$gopath" 2>/dev/null || gopath=/tmp/flume-go-cache
mkdir -p "$gopath"
export GOPATH="$gopath"

# ---- deliverable ----
if [ ! -f /app/lib/cache/cache.go ]; then
    fail "deliverable /app/lib/cache/cache.go missing"
fi

# ---- 1) fixture integrity ----
ref_sha=$(sha256sum /app/lib/serial/serial.go | cut -d' ' -f1)
if [ "$ref_sha" != "98f62fd715f4590ca72a7020342f5c03d52bdce3e202f0bac2be4ce22ddf0e0f" ]; then
    fail "lib/serial/serial.go was modified (sha256 $ref_sha); the reference baseline must stay pristine"
fi
vis_test_sha=$(sha256sum /app/lib/cache/cache_test.go | cut -d' ' -f1)
if [ "$vis_test_sha" != "886e5d67996c6a467909d261e4110a393afa1dcfeb819e7bd989df83ecea50d8" ]; then
    fail "lib/cache/cache_test.go was modified; the visible test suite must stay pristine"
fi
thr_test_sha=$(sha256sum /app/lib/cache/throughput_test.go | cut -d' ' -f1)
if [ "$thr_test_sha" != "1fc8a9e5a61755690adceb2fb493a23ff6336a6fe9d618c22fa270b474bc3947" ]; then
    fail "lib/cache/throughput_test.go was modified; the visible calibration test must stay pristine"
fi

# ---- inject the hidden test cases into the cache package ----
mkdir -p /app/lib/cache
n_hidden=0
for case_dir in /tests/hidden/*/; do
    [ -d "$case_dir" ] || continue
    for f in "$case_dir"hidden_*_test.go; do
        [ -f "$f" ] || continue
        cp "$f" /app/lib/cache/
        n_hidden=$((n_hidden + 1))
    done
done
if [ "$n_hidden" -lt 2 ]; then
    fail "expected >= 2 hidden test cases to inject, found $n_hidden"
fi
echo "injected $n_hidden hidden test files into /app/lib/cache/"

# ---- 2) race & correctness gate: suite 5x under the race detector ----
rm -f /tmp/flume-race.out
( cd /app && go test -vet=off -race -count=5 ./... ) > /tmp/flume-race.out 2>&1
race_rc=$?
n_races=$(grep -c "WARNING: DATA RACE" /tmp/flume-race.out 2>/dev/null || true)
if [ "$race_rc" != 0 ]; then
    fail "go test -race -count=5 ./... exited $race_rc (must be 0)"
elif [ "$n_races" != 0 ]; then
    fail "race detector reported $n_races data race(s) in the run"
fi
grep -E "^FAIL|WARNING: DATA RACE" /tmp/flume-race.out | head -20 | sed 's/^/  racegate| /' || true

# ---- 3) throughput floor via the verifier-owned benchmark ----
# Run the benchmark three times and keep the best (largest) ratio: a
# transient load spike on this shared host during the parallel window
# would otherwise unfairly drag a correct concurrent fix below the floor.
mkdir -p /app/bench
cp /tests/bench/main.go /app/bench/main.go
cd /app
best_ratio=""
for trial in 1 2 3; do
    bench_out=$(go run cachekit/bench 2>&1)
    bench_rc=$?
    echo "$bench_out" | sed "s/^/  bench$trial| /"
    if [ "$bench_rc" != 0 ]; then
        fail "go run cachekit/bench (trial $trial) exited $bench_rc"
        continue
    fi
    ratio=$(echo "$bench_out" | grep -o 'flume_ratio=[0-9.]*' | tail -1 | cut -d= -f2)
    if [ -z "$ratio" ]; then
        fail "benchmark trial $trial printed no flume_ratio=... line"
        continue
    fi
    if [ -z "$best_ratio" ] || python3 -c "exit(0 if float('$ratio') > float('$best_ratio') else 1)"; then
        best_ratio="$ratio"
    fi
done
if [ -z "$best_ratio" ]; then
    fail "benchmark produced no usable flume_ratio"
else
    ok=$(python3 -c "print(1 if float('$best_ratio') >= $FLOOR else 0)")
    if [ "$ok" != 1 ]; then
        fail "flume_ratio=$best_ratio is below the floor $FLOOR (hot path must not be serialized)"
    fi
fi

# ---- verdict ----
if [ "$failures" -gt 0 ]; then
    echo
    echo "flume-oar verifier: $failures failure(s)"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
echo
echo "flume-oar verifier: ALL PASS (races=0, hidden=$n_hidden, flume_ratio=$best_ratio >= $FLOOR)"
echo "1" > /logs/verifier/reward.txt
exit 0