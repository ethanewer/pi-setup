#!/bin/bash
# Oracle for spile-wharf: applies the minimal upstream fix to the psutil
# checkout at /app/src (colon-split parsing in psutil/_pslinux.py
# swap_memory()), installs the reproduction deliverable, and verifies both
# directions with the project's own tooling.
set -e

python3 /solution/apply_fix.py
cp /solution/reproduce.py /app/reproduce.py

echo "== own reproduction, against a pristine pre-fix tree (must crash) =="
cd /tmp
PYTHONPATH=/opt/pristine python3 -c 'import psutil; print("psutil from", psutil.__file__)'
set +e
PYTHONPATH=/opt/pristine python3 /app/reproduce.py
rc=$?
set -e
echo "pristine run exit code: $rc"
test "$rc" -ne 0

echo "== own reproduction, against the repaired tree (must print figures) =="
python3 /app/reproduce.py

echo "== the project's own regression test =="
cd /app/src
python -m pytest tests/test_linux.py::TestSwapMemory::test_no_space_after_colon -p no:cacheprovider