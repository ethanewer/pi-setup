#!/bin/bash
# larch-cipher oracle: writes the master program /app/finetune.py by doing the
# work, then RUNS it on the visible case to produce every deliverable in /app.
# It never reads /tests.
set -euo pipefail

install -m 0644 /solution/finetune.py /app/finetune.py
chmod +x /app/finetune.py

cd /app
python3 /app/finetune.py /app/case /app

# Every declared deliverable must be produced in /app by the run above.
for f in \
  /app/head.pt \
  /app/adapter_merged.pt \
  /app/state_dict.pkl \
  /app/eval_metrics.json \
  /app/embeddings.npy \
  /app/classifier.pkl \
  /app/lora_adapter/adapter_config.json \
  /app/lora_adapter/adapter_weights.safetensors
 do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done