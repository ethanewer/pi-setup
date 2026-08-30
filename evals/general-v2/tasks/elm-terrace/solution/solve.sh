#!/bin/bash
# Oracle for elm-terrace: install the real authoring deliverables and RUN them
# so every /app artifact is actually produced by the pipeline (never a cat'd
# precomputed answer). This oracle never reads /tests.
set -euo pipefail

install -m 0755 /solution/reconstruct.py /app/reconstruct.py
install -m 0755 /solution/triton_cpu.py  /app/triton_cpu.py

# 1) prove the general reconstructor works on the committed dict
python3 /app/reconstruct.py load /opt/causal/data/state_dict.pt /tmp/committed.pt

# 2) run the real tuning/publishing pipeline (writes model/, preds.csv,
#    sample.csv, lowrank.npz into /app)
python3 /app/reconstruct.py run

# 3) run the Triton CPU-interpreter deliverable (writes lt_triton_result.json)
python3 /app/triton_cpu.py

test -f /app/model/adapter_config.json || { echo "missing adapter_config"; exit 1; }
test -f /app/model/state_dict.pt     || { echo "missing state_dict.pt"; exit 1; }
test -f /app/model/arch.json         || { echo "missing arch.json"; exit 1; }
test -f /app/preds.csv                || { echo "missing preds.csv"; exit 1; }
test -f /app/sample.csv               || { echo "missing sample.csv"; exit 1; }
test -f /app/lowrank.npz              || { echo "missing lowrank.npz"; exit 1; }
test -f /app/lt_triton_result.json    || { echo "missing triton result"; exit 1; }
echo "oracle ok"