#!/usr/bin/env bash
# Oracle for tern-delta: install the module, run the visible calibration.
set -euo pipefail
# Use python3 from PATH, which is the interpreter the verifier uses and the one
# `pip install numpy` in the Dockerfile targets. On this base image PATH resolves
# to /usr/local/bin/python3 (3.12) while /usr/bin/python3 is Debian's 3.13, a
# different installation that has never seen this task's numpy; preferring the
# latter made the module import fail with ModuleNotFoundError, so the visible
# calibration never ran and /app/calibrated.json was never written.
py=python3

install -m 0644 /solution/calib.py /app/calib.py

cd /app
$py /app/calib.py
cat /app/calibrated.json
echo "solve.sh done"
