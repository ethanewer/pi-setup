#!/bin/bash
# amber-quarry oracle: install the pure-numpy mirror, run it on the visible
# case's fixed inputs to produce /app/answer.npz. Never reads /tests.
set -euo pipefail

install -m 0644 /solution/mirror.py /app/mirror.py
chmod +x /app/mirror.py

cd /app
python3 /app/mirror.py /app/case/model.onnx /app/case/inputs_fixed.npz /app/answer.npz

for f in /app/mirror.py /app/answer.npz; do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done

echo "solve.sh done -> /app/mirror.py + /app/answer.npz"
ls -l /app/mirror.py /app/answer.npz
