#!/bin/bash
# Oracle for gale-jetty. Does the REAL work: writes the delivered programs
# (reconcile driver, runnable extraction engine, parallel wrapper that reuses
# the sequential constant by import), then RUNS the driver to produce the
# deliverables (/app/mart.npy, /app/sheet.jsonl, ledger dirs, prompts/inference,
# ranked.json, mismatch.txt) from the fixtures in /app. Never reads /tests.
set -euo pipefail

# 1. The parallel wrapper must import the sequential constant (never restate it).
cat > /app/compute_parallel.py <<'PY'
#!/usr/bin/env python3
from compute_seq import ITERATIONS

__all__ = ["ITERATIONS"]
PY

# 2. The runnable extraction engine that actually writes the recovered matrix.
cp /solution/extract.py /app/extract.py

# 3. The reconcile driver.
cp /solution/reconcile.py /app/reconcile.py

chmod +x /app/reconcile.py /app/extract.py /app/compute_parallel.py

# 4. Run the driver for real to produce every deliverable in /app.
python3 /app/reconcile.py --input /app --output /app

# 5. Sanity: the matrix deliverable exists and needs rows.
python3 - <<'PY'
import numpy as np, os
m = np.load('/app/mart.npy')
assert m.shape == (5, 3), m.shape
print("oracle: mart.npy", m.shape, "ok")
assert os.path.exists('/app/sheet.jsonl')
assert open('/app/mismatch.txt').read().strip() == '404'
assert open('/app/prompts.txt').read().strip().splitlines()[0].startswith('prompt[1]')
print("oracle: close-out deliverables ok")
PY
