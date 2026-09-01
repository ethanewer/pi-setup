#!/bin/bash
# Oracle for flint-hollow: install the real Flask triage service at
# /app/app.py (the genuine work), then RUN its batch mode on the visible
# fixture to produce /app/answer.json. Never reads /tests.
set -euo pipefail
mkdir -p /app

cp /solution/app.py /app/app.py
chmod +x /app/app.py

# Smoke: serve mode must boot and answer /health (real work, then shutdown).
python3 /app/app.py --serve --port 5991 &
SRV_PID=$!
ok=0
for i in $(seq 1 20); do
  if python3 - <<'PY' 2>/dev/null
import json, urllib.request
with urllib.request.urlopen("http://127.0.0.1:5991/health", timeout=5) as r:
    assert json.load(r) == {"ok": True}
PY
  then ok=1; break; fi
  sleep 0.5
done
kill $SRV_PID 2>/dev/null || true
wait $SRV_PID 2>/dev/null || true
[ "$ok" = "1" ] || { echo "oracle: health smoke failed" >&2; exit 1; }

# Produce the visible-case deliverable with the batch mode.
python3 /app/app.py --classify-file /app/visible_cases.json /app/answer.json

echo "solve.sh done -> /app/app.py and /app/answer.json"
