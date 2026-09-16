#!/bin/bash
# Oracle for pintle-flint: applies the exact upstream fix to the scikit-image
# checkout at /app/src, installs the agent's deliverable reproduction
# (/app/repro.py), and proves both agree on the repaired tree.
set -e

python3 /solution/fix_regionprops.py /app/src/skimage/measure/_regionprops.py

# The deliverable reproduction (agent's task; the oracle supplies the same
# contract so the task is provably passable).
cp /solution/repro_solution.py /app/repro.py
chmod +x /app/repro.py

echo "== reproduction after the fix =="
cd /app/src
python3 /app/repro.py

echo "== upstream regression test extracted to /opt/golden =="
python3 -m pytest /opt/golden/test_regionprops.py::test_disabled_cache_is_empty -q -p no:cacheprovider