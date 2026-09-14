#!/bin/bash
# Oracle for brackish-deepwater: writes the agent-facing reproduction
# deliverable /app/repro.sh, applies the minimal upstream fix to the duckdb
# checkout at /app/src (early return from StringValueScanner::
# ProcessOverBufferValue when the CARRY_ON newline-consuming loop consumed
# characters without adding a row and the previous buffer already counted the
# row), then rebuilds incrementally and runs the project's own regression
# test, the parallel-CSV suites, and the reproduction against the repaired
# tree.
set -e

echo "== writing the reproduction deliverable =="
cat > /app/repro.sh <<'REPRO_EOF'
#!/bin/bash
# Reproduction for the parallel-CSV double-count bug.
# Usage: repro.sh [DUCKDB_BIN]   (default /app/src/build/release/duckdb)
set -u
BIN=${1:-/app/src/build/release/duckdb}
F=/app/src/data/csv/test/rrrn_parallel_test.csv
Q="SELECT (SELECT COUNT(*) FROM read_csv('$F', auto_detect=false, header=true, delim=',', columns={'id':'BIGINT','val':'VARCHAR'}, strict_mode=false, ignore_errors=true, max_line_size=2048, buffer_size=4096, parallel=true)) AS pc, (SELECT COUNT(*) FROM read_csv('$F', auto_detect=false, header=true, delim=',', columns={'id':'BIGINT','val':'VARCHAR'}, strict_mode=false, ignore_errors=true, max_line_size=2048, buffer_size=4096, parallel=false)) AS sc;"
out=$("$BIN" -csv -c "PRAGMA verify_parallelism; $Q" 2>&1)
row=$(printf '%s\n' "$out" | grep -E '^[0-9]+,[0-9]+$' | head -1)
if [ "$row" = "10000,10000" ]; then
  echo "REPRO-PASS"
  exit 0
else
  echo "REPRO-FAIL (parallel,sequential = ${row:-$out})"
  exit 1
fi
REPRO_EOF
chmod +x /app/repro.sh

echo "== applying the minimal upstream fix =="
python3 /solution/fix_csv_scanner.py /app/src

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
check_unittest "test/sql/copy/csv/parallel/test_rrrn_parallel.test"

echo "== project's own parallel-CSV suites =="
for s in \
  "test/sql/copy/csv/parallel/test_parallel_csv.test" \
  "test/sql/copy/csv/parallel/csv_parallel_buffer_size.test" \
  "test/sql/copy/csv/parallel/csv_parallel_null_option.test" \
  "test/sql/copy/csv/parallel/test_parallel_error_messages.test" \
  "test/sql/copy/csv/parallel/test_multiple_files.test" \
  "test/sql/copy/csv/parallel/parallel_csv_union_by_name.test" \
  "test/sql/copy/csv/parallel/parallel_csv_hive_partitioning.test"; do
  check_unittest "$s"
done

echo "== reproduction against the repaired engine =="
/app/repro.sh > /tmp/oracle-repro.out 2>&1 || {
  echo "FAIL: /app/repro.sh did not pass against the repaired tree" >&2
  cat /tmp/oracle-repro.out >&2
  exit 1
}
grep -q "REPRO-PASS" /tmp/oracle-repro.out

echo "OK: golden test, suites, and reproduction all pass on the fixed tree"