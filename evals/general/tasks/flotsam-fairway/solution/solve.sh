#!/bin/bash
# Oracle for flotsam-fairway: applies the upstream fix for the printf %c
# invalid-UTF-8 bug to the duckdb checkout at /app/src (validate the format
# result as UTF-8 in the path shared by printf and format and raise a clean
# InvalidInputException pointing at chr()), rebuilds incrementally, installs
# the /app/reproduce.sh deliverable, and proves the result with the project's
# own golden regression test, the project's own string-function suite, and
# the reproduction run against both the repaired and the preserved pre-fix
# engine.
set -e

echo "== 1. apply the fix to /app/src =="
python3 /solution/fix_printf.py

echo "== 2. incremental rebuild =="
cd /app/src
touch extension/core_functions/scalar/string/printf.cpp
ninja -C build/release -j1

echo "== 3. install the reproduction deliverable =="
cp /solution/reproduce.sh /app/reproduce.sh
chmod +x /app/reproduce.sh

echo "== 4. the project's own golden regression test =="
cp /opt/golden/test_printf.test test/sql/function/string/test_printf.test
build/release/test/unittest "test/sql/function/string/test_printf.test" 2>&1 | tail -3
# restore the pinned parent's regression data (the trial tree must only carry
# the code fix)
cp /opt/golden/test_printf.parent.test test/sql/function/string/test_printf.test

echo "== 5. the project's own string-function suite =="
build/release/test/unittest "test/sql/function/string/*" 2>&1 | tail -3

echo "== 6. reproduction legs =="
echo "-- repaired engine:"
rc=0; /app/reproduce.sh /app/src/build/release/duckdb || rc=$?
echo "reproduce.sh rc=$rc"
echo "-- preserved pre-fix engine:"
rc=0; /app/reproduce.sh /opt/pristine/duckdb || rc=$?
echo "reproduce.sh rc=$rc"
echo "oracle done"