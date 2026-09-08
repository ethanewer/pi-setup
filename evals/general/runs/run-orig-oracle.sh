#!/usr/bin/env bash
# Decisive check: did binarizing break these oracles, or were they already short
# of full credit and partial reward was hiding it?
#
# Runs harbor's oracle agent (no model) over the four tasks in question with the
# PRE-binarization tests/test.sh restored from commit 509a2a5e. If the original
# verifier also fails to reach 1.0, the shortfall predates the change.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
export PYTHONPATH=$EVAL/agents
cd "$EVAL"

echo "[orig] $(date -Is) START"
"$HARBOR" run -p /tmp/orig-oracle -n 4 -k 1 -y -q \
  --job-name v33-oracle-original -o "$OUT" -a oracle \
  > "$OUT/v33-oracle-original.harness.log" 2>&1
echo "[orig] $(date -Is) DONE rc=$?"

python3 - <<'PY'
from pathlib import Path
import json
job = Path('/home/ee/general-eval-runs/jobs/v33-oracle-original')
print('ORIGINAL (pre-binarization) verifier, oracle agent:')
for rp in sorted(job.glob('*__*/verifier/reward.txt')):
    td = rp.parent.parent
    task = td.name.split('__')[0]
    raw = rp.read_text().strip()
    exc = None
    rj = td / 'result.json'
    if rj.exists():
        try:
            exc = (json.loads(rj.read_text()).get('exception_info') or {}).get('exception_type')
        except Exception:
            pass
    verdict = 'full credit' if raw.replace('.', '').strip('0') in ('1', '') and float(raw or 0) >= 1.0 else 'SHORT OF 1.0'
    print(f'  {task:22s} original_reward={raw:8s} {verdict}  exception={exc}')
PY
echo "[orig] ORIGINAL_ORACLE_FINISHED"
