#!/bin/bash
# Verifier for ballast-deepwater: an upstream-clone debugging task on
# duckdb/duckdb.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# subtracting an interval whose microseconds component is INT64_MIN from a
# TIME/TIMETZ value silently returns a wrong time (signed negation overflow),
# and the same unchecked negation in Interval::Invert affects DATE/TIMESTAMP
# subtraction. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression-test file the
#      image overlays into test/sql/types/ is byte-identical to the upstream
#      regression test, the two source files hold non-empty diffs and
#      nothing else in the repository changed);
#   1. rebuilds from the repaired tree (incremental, ~minutes at 1 CPU) and
#      requires the project's own regression test
#      test_interval_negation_overflow.test to pass through the project's own
#      test runner (build/release/test/unittest), plus the project's own
#      interval and time-of-day sqllogictest suites to stay green;
#   2. runs authored hidden cases through the rebuilt CLI binary: TIME /
#      TIMETZ / DATE / TIMESTAMP subtractions that hit the same code path
#      from inputs the upstream test does not use, asserting the exact
#      out-of-range error messages, plus normal-arithmetic sanity checks
#      asserting exact correct values.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=8616efa9da9921b9111fe46373af7936a5d96d16
FIX_SHA=b94555b59e58941bf42da1aeb8f3251850b85e8f
GOLDEN_SHA=18eb13b803bdd798b6596f071743911136f090e4709779f8152797180ae3bc57
GOLDEN=/opt/golden/test_interval_negation_overflow.test
SRC_TEST=test/sql/types/test_interval_negation_overflow.test

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- src/common/types/interval.cpp 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: src/common/types/interval.cpp differs from the pinned commit"
fi
if [ -z "$(git -C "$SRC" diff -- src/function/scalar/operator/subtract.cpp 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: src/function/scalar/operator/subtract.cpp differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$SRC_TEST" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: $SRC_TEST is byte-identical to the upstream regression test"
else
  fail "$SRC_TEST was altered (${tree_golden:-missing})"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M src/common/types/interval.cpp"$'\n'" M src/function/scalar/operator/subtract.cpp"$'\n'"?? $SRC_TEST"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression data"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. rebuild and run the project's own suites -----------------------
echo "== incremental rebuild from the repaired tree =="
# Force a real relink of the project binaries. Touching the two fixed sources
# guarantees ninja must recompile them and relink libduckdb, the duckdb CLI and
# the unittest runner from the agent's actual sources, so any binary the agent
# planted (wrapper script, ELF decoy) is overwritten by the freshly built one.
if ( cd "$SRC" && touch src/common/types/interval.cpp src/function/scalar/operator/subtract.cpp \
     && ninja -C build/release -j2 > /tmp/rebuild.log 2>&1 ); then
  echo "ok: incremental rebuild (forced relink) succeeded"
else
  fail "incremental rebuild failed"
  tail -30 /tmp/rebuild.log | sed 's/^/    /' >&2 || true
fi
if [ ! -x "$SRC/build/release/duckdb" ]; then
  fail "the project binary build/release/duckdb is missing"
fi
if [ ! -x "$SRC/build/release/test/unittest" ]; then
  fail "the project test runner build/release/test/unittest is missing"
fi
# The binaries must be real ELF executables produced by the relink above, not
# scripts the agent substituted for the project's own engine and runner.
is_elf() {  # is_elf BIN
  local magic
  magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$magic" = "7f454c46" ]
}
for bin in "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"; do
  if is_elf "$bin"; then
    echo "ok: $bin is a real ELF executable"
  else
    fail "$bin is not an ELF executable: $(ls -l "$bin" | awk '{print $1, $5}' || echo missing)"
  fi
done

echo "== the project's own regression test for this bug =="
if [ "$reward" = 1 ]; then
  ( cd "$SRC" && build/release/test/unittest "$SRC_TEST" > /tmp/golden.out 2>&1 )
  if grep -qE "All tests passed" /tmp/golden.out 2>/dev/null; then
    echo "ok: Catch summary: all tests passed for the golden test"
  else
    fail "the golden regression test did not pass end to end"
    tail -25 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "== the project's own interval and time suites =="
suite_ok=1
if [ "$reward" = 1 ]; then
  for flt in "test/sql/types/interval/*" "test/sql/types/time/test_time.test" \
             "test/sql/types/time/test_time_tz.test" "test/sql/types/time/time_limits.test" \
             "test/sql/types/time/time_parsing.test"; do
    if ( cd "$SRC" && build/release/test/unittest "$flt" > "/tmp/suite-$(basename "$flt" | tr '/.' '__').out" 2>&1 ) \
       && grep -qE "All tests passed" "/tmp/suite-$(basename "$flt" | tr '/.' '__').out"; then
      echo "ok: suite '$flt' green"
    else
      fail "suite '$flt' is not green"
      tail -12 "/tmp/suite-$(basename "$flt" | tr '/.' '__').out" 2>/dev/null | sed 's/^/    /' >&2 || true
      suite_ok=0
    fi
  done
fi

# ---------- 2. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
n_failed=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  qf="$case"queries.txt
  [ -f "$qf" ] || { fail "hidden case $(basename "$case") has no queries.txt"; n_failed=$((n_failed+1)); continue; }
  n_hidden=$((n_hidden + 1))
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    q=${line%%$'\t'*}
    expect=${line#*$'\t'}
    out=$("$SRC/build/release/duckdb" -c "$q" 2>&1)
    rc=$?
    case "$expect" in
      ERROR:*) substr=${expect#ERROR:}
        if printf '%s' "$out" | grep -Fq "$substr"; then
          echo "ok: hidden $(basename "$case") line $lineno (error) matches"
        else
          fail "hidden $(basename "$case") line $lineno: expected error containing '$substr'; got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
          n_failed=$((n_failed+1))
        fi ;;
      VALUE:*) substr=${expect#VALUE:}
        if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -Fq "$substr"; then
          echo "ok: hidden $(basename "$case") line $lineno (value) matches"
        else
          fail "hidden $(basename "$case") line $lineno: expected value containing '$substr'; got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
          n_failed=$((n_failed+1))
        fi ;;
      *) fail "hidden $(basename "$case") line $lineno: bad expectation '$expect'"; n_failed=$((n_failed+1)) ;;
    esac
  done < "$qf"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo
echo "hidden cases exercised: $n_hidden, failed lines: $n_failed"
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0