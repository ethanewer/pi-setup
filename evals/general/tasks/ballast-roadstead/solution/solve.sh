#!/bin/bash
# Oracle for ballast-roadstead: applies the debug-resolve marker fix to the
# poetry checkout at /app/src, then re-runs the visible reproduction to show
# the user-visible symptom is gone. The full verdict (upstream golden test,
# the project's own debug-command suite and the hidden cases) is the
# verifier's job and runs on this same repaired tree.
set -e

python3 /solution/fix_resolve.py /app/src

echo "== reproduction output after the fix =="
cd /app/src
/opt/poetry-venv/bin/python /app/probe_resolve.py

echo "== oracle done =="