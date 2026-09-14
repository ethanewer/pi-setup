#!/bin/bash
# Oracle for jackstay-larboard: reproduces, fixes and proves the boolean
# colourbar defect in the real librosa tree at /app/src.
set -euo pipefail

cd /app/src
test "$(git rev-parse HEAD)" = "c7aa2ce80a100cd901945589437c5acc55e38739" \
    || { echo "oracle: /app/src is not at the pinned parent commit"; exit 1; }

# 1) the fix (the real work; /solution/apply_fix.py does a surgical text edit)
python3 /solution/apply_fix.py

# 2) deliverables
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh
cp /solution/writeup.md /app/summary.md

# 3) prove both directions with the deliverables themselves:
#    fixed tree must pass, pristine pre-fix concept must fail
LIBROSA_TREE=/app/src /app/repro.sh
if LIBROSA_TREE=/opt/prefix /app/repro.sh; then
    echo "oracle: repro unexpectedly passed against the pre-fix package at /opt/prefix"
    exit 1
fi
echo "oracle: repro fails on pre-fix concept, passes on repaired tree — done"