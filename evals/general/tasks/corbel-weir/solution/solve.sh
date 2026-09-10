#!/bin/bash
# corbel-weir oracle: ship the click 8.5.0 release from the /app/src checkout.
set -euo pipefail
cp /solution/solver.py /app/solver.py
python3 /app/solver.py
for f in /app/dist/click-8.5.0-py3-none-any.whl \
         /app/dist/click-8.5.0.tar.gz \
         /app/dist/release-proof.json; do
  [ -f "$f" ] || { echo "oracle did not produce $f" >&2; exit 1; }
done