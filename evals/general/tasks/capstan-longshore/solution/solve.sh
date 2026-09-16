#!/bin/bash
# Oracle for capstan-longshore: applies the minimal upstream fix to the duckdb
# checkout at /app/src (report missing named parameters in declaration order
# instead of hash-map iteration order in PreparedStatement::MissingValuesException),
# then rebuilds incrementally and runs the project's own regression test plus the
# prepared-statement suite against the repaired tree.
set -e

python3 /solution/fix_prepared_statement.py /app/src/src/include/duckdb/main/prepared_statement.hpp

echo "== incremental rebuild =="
cd /app/src && ninja -C build/release -j1

# The unittest binary (Catch2) returns 0 even when sqllogictest cases fail, so
# each run is checked by requiring Catch's passing summary line.
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
check_unittest "test/sql/prepared/prepared_named_param.test"

echo "== the project's own prepared-statement suite =="
check_unittest "test/sql/prepared/*"

echo "== CLI spot check: missing parameters in declaration order =="
out=$(/app/src/build/release/duckdb -c 'PREPARE q03 AS SELECT $aa, $bb, $cc, $dd, $ee; EXECUTE q03(aa := 1, bb := 2);' 2>&1) || true
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q "parameters: cc, dd, ee" \
  || { echo "FAIL: CLI did not report the missing parameters in declaration order" >&2; exit 1; }

echo "== deliverable: root-cause note =="
python3 - <<'EOF'
note = """Root cause

Executing a prepared statement that uses named parameters checks which
declared parameters were not supplied and raises an error listing those
names. PreparedStatement::MissingValuesException
(src/include/duckdb/main/prepared_statement.hpp) collected the missing names
into an identifier_set_t -- an unordered (hash) set -- and joined that set in
its iteration order. Hash-bucket order has nothing to do with the order in
which the parameters appear in the statement, so the error could list the
missing parameters in any order (e.g. 'ee, cc, dd' for a statement declaring
aa, bb, cc, dd, ee), and could change from build to build or name set to name
set, confusing users and tools that parse the message.

Fix

Collect (declaration index, name) pairs for the missing parameters and sort
them by declaration index before building the message, so the error always
lists the missing parameters in the order they are declared:
'Values were not provided for the following parameters: cc, dd, ee'.
"""
open('/app/explanation.md', 'w', encoding='utf-8').write(note)
print('wrote /app/explanation.md')
EOF

echo "== oracle: all steps passed =="