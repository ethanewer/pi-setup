#!/bin/bash
# Oracle for ballast-rudder: applies the multi-assignment overload
# reinference fix to the mypy checkout (/app/src), re-runs the reproduction,
# and runs the upstream regression test extracted into /opt/golden/ at image
# build time. The tree is left with only the fix applied.
set -e

python3 /solution/fix_checker.py /app/src/mypy/checker.py

echo "== reproduction output after the fix =="
set +e
(
  cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py
)
rc=$?
set -e
echo "[repro exit code: $rc (must be 1: real diagnostics, no INTERNAL ERROR)]"
test "$rc" -eq 1

echo "== upstream regression test =="
cd /app/src
cp /opt/golden/check-tuples.test test-data/unit/check-tuples.test
python3 -m pytest mypy/test/testcheck.py \
  -k "testMultipleAssignmentWithOverloadReinferredAsHomogeneousTuple or testMultipleAssignmentWithOverloadReinferredAsNonTuple" \
  -o addopts="" -q -p no:cacheprovider
# Restore the tree so only the fix remains (the verifier re-copies the golden
# file itself at trial time).
git checkout -q -- test-data/unit/check-tuples.test

echo "== oracle done =="