#!/bin/bash
# Oracle for garboard-yard: applies the minimal upstream fix to the psutil
# checkout at /app/src (process_iter() must yield a process whose attribute
# prefetch raises the zombie-process condition instead of dropping it from the
# cache), writes the deterministic reproduction deliverable, and proves the
# contract from the instruction: reproduction fails on the buggy tree, passes
# once the library is fixed, and the project's own enumeration test class is
# green.
set -e

python3 /solution/apply_fix.py /app/src/psutil/__init__.py
cp /solution/reproduce_zombie_skip.py /app/reproduce_zombie_skip.py

echo "== reproduction against the repaired tree (must pass) =="
python3 /app/reproduce_zombie_skip.py

echo "== project's own enumeration test class (TestProcessIter) =="
cd /app/src && python3 -m pytest tests/test_system.py -k TestProcessIter -q -p no:cacheprovider