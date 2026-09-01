#!/usr/bin/env bash
# Oracle for tern-delta: install the module, run the visible calibration.
set -euo pipefail
py=/usr/bin/python3
[ -x "$py" ] || py=python3

install -m 0644 /solution/calib.py /app/calib.py

cd /app
$py /app/calib.py
cat /app/calibrated.json
echo "solve.sh done"
