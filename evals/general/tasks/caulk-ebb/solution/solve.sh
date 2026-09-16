#!/bin/bash
# Oracle for caulk-ebb: networkx geometric_soft_configuration_graph computes
# the mean hidden degree from a kappas mapping by summing the mapping's KEYS
# instead of its values (upstream issue #8726), so string node labels crash
# with a TypeError and integer labels silently act as the degrees.
#
# The oracle does the real work:
#   1. write the reproduction deliverable /app/reproduce_failure.py,
#   2. run it against the unmodified (buggy) tree: it must FAIL, proving the
#      deliverable really demonstrates the bug,
#   3. apply the one-line upstream fix to /app/src/networkx/generators/geometric.py,
#   4. run the reproduction again: it must now PASS, and the project's own
#      regression test module must stay green.
set -euo pipefail

cp /solution/reproduce_failure.py /app/reproduce_failure.py
chmod +x /app/reproduce_failure.py

echo "== reproduction against the buggy tree (must fail) =="
set +e
(cd /app && python3 reproduce_failure.py)
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "oracle error: the reproduction did not fail on the buggy tree" >&2
  exit 1
fi
echo "reproduction failed as expected on the buggy tree (rc=$rc)"

echo "== applying the fix =="
python3 /solution/apply_fix.py

echo "== reproduction against the fixed tree (must pass) =="
(cd /app && python3 reproduce_failure.py)

echo "== project's own generator test module (must stay green) =="
(cd /app/src/networkx/generators && python3 -m pytest tests/test_geometric.py -o addopts="" -q -p no:cacheprovider)

echo "oracle done"