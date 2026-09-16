#!/bin/bash
# Oracle for strake-offing: reproduces, fixes and proves the Axes.hist
# timedelta-input crash in the real matplotlib tree at /app/src.
set -euo pipefail

cd /app/src
test "$(git rev-parse HEAD)" = "496ae85214a7029d5c8eca320cb45f013b535dfe" \
    || { echo "oracle: /app/src is not at the pinned parent commit"; exit 1; }

# 1) the fix (the real work; /solution/apply_fix.py does a surgical text edit)
python3 /solution/apply_fix.py

# 2) deliverables
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh
cp /solution/repro_main.py /app/repro_main.py
cp /solution/writeup.md /app/summary.md

# 3) prove both directions with the deliverables themselves:
#    fixed tree must pass, pristine pre-fix concept must fail
MPL_TREE=/app/src /app/repro.sh
if MPL_TREE=/opt/prefix MESONPY_EDITABLE_SKIP=/app/src/build/cp312 \
        PYTHONPATH=/opt/prefix/lib /app/repro.sh; then
    echo "oracle: repro unexpectedly passed against the pre-fix package at /opt/prefix"
    exit 1
fi
echo "oracle: repro fails on pre-fix concept, passes on repaired tree — done"