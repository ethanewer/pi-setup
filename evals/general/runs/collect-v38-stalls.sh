#!/usr/bin/env bash
# Collect the eight re-run trials into the published layout.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
rm -rf /tmp/t2-stalls; mkdir -p /tmp/t2-stalls
python3 "$EVAL/tools/collect_task_records.py" --jobs "$JOBS" --out /tmp/t2-stalls \
  --allow-missing \
  --job "v38-t2-dsk-stalls:terminus-2:deepseek/deepseek-v4-flash-0731:openrouter/deepseek/deepseek-v4-flash-0731" \
  > /tmp/t2-stalls.log 2>&1
echo "collected: $(find /tmp/t2-stalls -name trajectory.json | wc -l)"
# binarize under the documented contract: new = 1 iff old >= 1.0
python3 - <<'PY'
from pathlib import Path
n=0
for rt in Path('/tmp/t2-stalls').rglob('verifier/reward.txt'):
    raw=rt.read_text().strip(); v=float(raw)
    norm='1' if v>=1.0 else '0'
    if norm!=raw: rt.write_text(norm+'\n'); n+=1
print('binarized:', n)
PY
grep -iE "ERROR|WARN" /tmp/t2-stalls.log | head -5
