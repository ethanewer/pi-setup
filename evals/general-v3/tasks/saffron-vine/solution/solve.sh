#!/bin/bash
# saffron-vine oracle: write the deliverable program /app/restore.py, then RUN
# it on the visible case to produce every artifact in /app. Never reads /tests.
set -euo pipefail

install -m 0644 /solution/restore.py /app/restore.py
chmod +x /app/restore.py

cd /app
python3 /app/restore.py /app/case /app

# Every declared deliverable must be produced in /app by the run above.
for f in \
  /app/restore.py \
  /app/adapter/adapter_config.json \
  /app/adapter/adapter_weights.safetensors \
  /app/adapter/feature_spec.json \
  /app/adapter_merged.pt \
  /app/eval_metrics.json
 do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done

echo "solve.sh done -> /app/restore.py + adapter artifacts"
ls -l /app/restore.py /app/adapter_merged.pt /app/eval_metrics.json /app/adapter/
