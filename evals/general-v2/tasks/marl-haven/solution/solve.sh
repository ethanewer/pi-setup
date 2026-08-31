#!/bin/bash
# Oracle for marl-haven: write the runnable extraction program, make it
# executable, and RUN it on the visible fixtures to produce /app/payload.npy.
# Never reads /tests.
set -euo pipefail

cp /solution/extract.py /app/extract.py
chmod +x /app/extract.py

python3 /app/extract.py /app/capture.bin /app/query.txt /app/payload.npy

# Sanity: deliverables exist and the matrix is well-formed.
python3 - <<'PY'
import numpy as np
m = np.load('/app/payload.npy')
assert m.dtype == np.float64, m.dtype
assert m.shape == (4, 4), m.shape  # 4 selected frame rows x 4 selected channels
print("oracle: payload.npy", m.shape, m.dtype, "ok")
PY

echo "solve.sh done -> /app/extract.py and /app/payload.npy"
ls -l /app/extract.py /app/payload.npy
