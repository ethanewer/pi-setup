#!/bin/bash
# Oracle for ballast-deepwater: applies the minimal upstream fix to the
# duckdb checkout at /app/src (bounds-check every signed negation of an
# interval field in SubtractTimeOperator::Operation and Interval::Invert),
# then rebuilds incrementally and runs the project's own regression test
# plus the interval/time suites against the repaired tree.
set -e

python3 /solution/fix_interval_negation.py /app/src

echo "== incremental rebuild =="
cd /app/src && ninja -C build/release

# The unittest binary returns 0 even when sqllogictest cases fail, so each
# run is checked by requiring Catch's passing summary line.
check_unittest() {  # check_unittest FILTER
  local filter=$1
  local out
  out=$(cd /app/src && build/release/test/unittest "$filter" 2>&1) || true
  if printf '%s\n' "$out" | grep -q "All tests passed"; then
    echo "ok: $filter"
  else
    echo "FAIL: unittest '$filter' did not pass:" >&2
    printf '%s\n' "$out" | tail -20 >&2
    exit 1
  fi
}

echo "== upstream regression test for this bug =="
check_unittest "test/sql/types/test_interval_negation_overflow.test"

echo "== interval + time-of-day suites =="
check_unittest "test/sql/types/interval/*"
check_unittest "test/sql/types/time/test_time.test"
check_unittest "test/sql/types/time/test_time_tz.test"
check_unittest "test/sql/types/time/time_limits.test"
check_unittest "test/sql/types/time/time_parsing.test"

echo "== CLI spot checks =="
/app/src/build/release/duckdb -c \
  "SELECT TIME '12:00:00' - INTERVAL '-4611686018427387904 microseconds -4611686018427387904 microseconds';" \
  > /tmp/oracle-check.out 2>&1 || true
grep -q "Out of Range Error: Interval micros value out of range" /tmp/oracle-check.out
/app/src/build/release/duckdb -c "SELECT DATE '2024-01-01' - INTERVAL '-2147483648 days';" \
  > /tmp/oracle-check2.out 2>&1 || true
grep -q "Out of Range Error: Interval days value out of range" /tmp/oracle-check2.out
echo "OK: extreme interval subtraction now raises the out-of-range errors"