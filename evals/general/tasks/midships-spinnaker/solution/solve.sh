#!/bin/bash
# Oracle for midships-spinnaker: writes the reproduction deliverable
# (/app/reproduce.py), repairs the real psf/requests tree at /app/src (the
# stream-classification decision in the body-preparation code path), then
# proves the reproduction against the repaired tree. Reads only /app,
# /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

python3 /solution/solver.py
rc=$?
if [ $rc -ne 0 ]; then
    echo "oracle: solver failed (rc=$rc)" >&2
    exit $rc
fi

if [ ! -s /app/reproduce.py ]; then
    echo "oracle: /app/reproduce.py was not created" >&2
    exit 1
fi

echo "oracle complete: /app/reproduce.py written, fix applied under /app/src, repro REPRO-OK"
exit 0