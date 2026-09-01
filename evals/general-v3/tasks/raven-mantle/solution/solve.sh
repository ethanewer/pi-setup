#!/bin/bash
# Real solution for raven-mantle: install the inference adapter and run the
# end-to-end default workflow so the deliverables are produced by real work.
set -euo pipefail

cp /solution/infer.py /app/infer.py
chmod +x /app/infer.py

python3 /app/infer.py workflow

# Sanity: the script, its two output deliverables, and the integrity of the
# committed engine checkpoint.
test -f /app/infer.py
test -s /app/loss.txt
test -s /app/batch_plan.json
python3 - <<'PY'
import json
cfg = json.load(open('/app/config.json'))
real = json.load(open('/app/out/milp.json'))
assert real['instance_count'] == 5 and len(real['logits']) == cfg['milp_classes']
print('raven-mantle solve ok')
PY