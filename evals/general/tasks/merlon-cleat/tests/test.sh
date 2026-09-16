#!/bin/bash
# Verifier for merlon-cleat (executes-deliverable).
#
# Grades /app/pennant, a Rust library whose frame encoder's hot path must be
# made allocation-free for the common case while keeping the documented
# public API source-compatible. Four families of checks:
#
#   1. the crate's own test suite is still green (cargo test);
#   2. two hidden consumer crates (tests/hidden/H1, H2) compile unchanged
#      against the crate and all their behavioral assertions pass;
#   3. a benchmark harness (tests/bench) built against BOTH the crate under
#      test and the pristine reference implementation at /opt/reference
#      measures the per-call heap allocations of encode_frame and the
#      wall-clock time of the hot loop;
#   4. the improvement is real: the measured allocation count of the
#      deliverable's hot path must be (nearly) zero while the reference
#      implementation measures millions, the wall-clock must improve 3x or
#      more, and both implementations must emit byte-identical frames.
#
# The allocation count is deterministic and cannot flake: the shim
# /opt/libcountallocs.so intercepts the malloc family and every run is
# single-threaded with a fixed-seed corpus. The wall-clock gate is secondary
# and has a >4x measured margin.
#
# Rewards: 1 only if every check passes; 0 otherwise. Every failure path
# writes 0 and exits 0 AFTER printing the failure list to stdout.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
FAILURES=()

fail() {
  FAILURES+=("$1")
  echo "FAIL: $1"
}

# ---------------------------------------------------------------- preconditions
CRATE=/app/pennant
SHIM=/opt/libcountallocs.so
export HOME=/tmp/verifyhome
export CARGO_HOME=/tmp/verifyhome/.cargo
export CARGO_NETWORK=false
mkdir -p "$HOME" "$CARGO_HOME" /tmp/verifywork

[ -d "$CRATE/" ] || fail "missing deliverable /app/pennant/"
[ -f "$CRATE/Cargo.toml" ] || fail "missing /app/pennant/Cargo.toml"
[ -x "$SHIM" ] || fail "missing allocation shim at /opt/libcountallocs.so"
[ -d /opt/reference/pennant/src ] || fail "missing reference implementation at /opt/reference/pennant"

if ! grep -q '^name *= *"pennant"' "$CRATE/Cargo.toml"; then
  fail "crate name must be pennant"
fi
if grep -qE '^\[dependencies' "$CRATE/Cargo.toml"; then
  fail "crate declares third-party dependencies; verification is offline"
fi

run_cargo() {  # logfile, workdir, args...
  local log="$1" wd="$2"
  shift 2
  ( cd "$wd" && cargo build --offline --release "$@" ) >"$log" 2>&1
}

# ------------------------------------------------------------- 1. crate tests
TESTLOG=/tmp/verifywork/crate-test.log
if ! ( cd "$CRATE" && cargo test --offline ) >"$TESTLOG" 2>&1; then
  fail "cargo test in the crate failed"
else
  total=$(grep -c '^test result: ok' "$TESTLOG" || true)
  failed=$(grep -c 'test result: FAILED' "$TESTLOG" || true)
  if [ "$failed" != "0" ] || [ "$total" -lt 4 ]; then
    fail "cargo test not green (ok-results=$total failed=$failed)"
  fi
fi
# the reference copy must also build (so the benchmark is honest)
if ! ( cd /opt/reference/pennant && cargo build --offline --release ) >/tmp/verifywork/ref-build.log 2>&1; then
  fail "reference implementation does not build"
fi

# ---------------------------------------------------- 2. hidden consumers
for case in H1 H2; do
  work=/tmp/verifywork/$case
  rm -rf "$work"
  cp -r /tests/hidden/$case "$work"
  rm -rf "$work/target"
  LOG=/tmp/verifywork/$case-build.log
  if ! run_cargo "$LOG" "$work"; then
    fail "hidden consumer $case does not compile against the crate"
    continue
  fi
  BIN=$(find "$work/target/release" -maxdepth 1 -type f -perm -u+x 2>/dev/null | head -1)
  [ -n "$BIN" ] || { fail "hidden consumer $case: no binary produced"; continue; }
  OUT=$("$BIN" 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    fail "hidden consumer $case exited $rc: $OUT"
  elif ! echo "$OUT" | grep -qE "^$case-OK "; then
    fail "hidden consumer $case did not report $case-OK"
  else
    echo "consumer $case: $(echo "$OUT" | grep -E "^$case-OK")"
  fi
done

# ------------------------------------------------------------- 3+4. benchmark
BWORK=/tmp/verifywork/bench
rm -rf "$BWORK"
cp -r /tests/bench "$BWORK"
rm -rf "$BWORK/target"
if ! run_cargo /tmp/verifywork/bench-build.log "$BWORK"; then
  fail "benchmark harness does not build"
fi
BIN=$(find "$BWORK/target/release" -maxdepth 1 -type f -perm -u+x 2>/dev/null | head -1)
if [ -z "$BIN" ]; then
  fail "benchmark harness produced no binary"
else
  run_bench() {  # mode, alloclog
    LD_PRELOAD="$SHIM" ALLOCLOG="$2" "$BIN" "$1" 2>/dev/null
  }
  LOAD_OUT=$(run_bench load /tmp/verifywork/load.alloc)
  REF_OUT=$(run_bench ref /tmp/verifywork/ref.alloc)
  AGENT_OUT=$(run_bench agent /tmp/verifywork/agent.alloc)
  BOTH_OUT=$("$BIN" both 2>/dev/null)

  load_allocs=$(sed -n 's/^ALLOCS=//p' /tmp/verifywork/load.alloc 2>/dev/null | head -1)
  ref_allocs=$(sed -n 's/^ALLOCS=//p' /tmp/verifywork/ref.alloc 2>/dev/null | head -1)
  agent_allocs=$(sed -n 's/^ALLOCS=//p' /tmp/verifywork/agent.alloc 2>/dev/null | head -1)

  ref_micros=$(echo "$BOTH_OUT" | sed -n 's/.*REF_MICROS=\([0-9]*\).*/\1/p' | head -1)
  agent_micros=$(echo "$BOTH_OUT" | sed -n 's/.*AGENT_MICROS=\([0-9]*\).*/\1/p' | head -1)
  same=$(echo "$BOTH_OUT" | sed -n 's/.*SAME=\([0-9]\) .*/\1/p' | head -1)
  ref_st=$(echo "$BOTH_OUT" | sed -n 's/.*REF_SELFTEST=\([0-9]\).*/\1/p' | head -1)
  agent_st=$(echo "$BOTH_OUT" | sed -n 's/.*AGENT_SELFTEST=\([0-9]\).*/\1/p' | head -1)

  if [ -z "$load_allocs" ] || [ -z "$ref_allocs" ] || [ -z "$agent_allocs" ]; then
    fail "benchmark did not produce allocation counts (shim problem?)"
  else
    ref_delta=$(( ref_allocs - load_allocs ))
    agent_delta=$(( agent_allocs - load_allocs ))
    echo "bench: ref allocs $ref_delta, candidate allocs $agent_delta (per common-case call the reference must allocate a lot; the candidate must allocate ~nothing)"
    if [ "$ref_delta" -lt 1500000 ]; then
      fail "reference implementation did not measure >=1.5M hot-loop allocations (got $ref_delta): the shim is not counting, so the gate would be vacuous"
    fi
    if [ "$agent_delta" -gt 16 ]; then
      fail "candidate hot path allocated $agent_delta times: the common case is not allocation-free"
    fi
  fi

  if [ -z "$ref_micros" ] || [ -z "$agent_micros" ]; then
    fail "benchmark did not produce timings"
  else
    echo "bench: reference ${ref_micros}us, candidate ${agent_micros}us (same-process A/B)"
    if [ $((agent_micros * 3)) -gt "$ref_micros" ]; then
      fail "candidate is not at least 3x faster than the reference ($agent_micros vs $ref_micros)"
    fi
  fi
  if [ "$same" != "1" ] || [ "$ref_st" != "1" ] || [ "$agent_st" != "1" ]; then
    fail "benchmark self-checks failed (SAME=$same REF_SELFTEST=$ref_st AGENT_SELFTEST=$agent_st)"
  fi
fi

# ------------------------------------------------------------------- reward
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo
  echo "FAILURES: ${#FAILURES[@]}"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo "0" > /logs/verifier/reward.txt
else
  echo
  echo "ALL PASS: crate green, both hidden consumers green, benchmark shows an allocation-free common case at >=3x speed"
  echo "1" > /logs/verifier/reward.txt
fi
exit 0