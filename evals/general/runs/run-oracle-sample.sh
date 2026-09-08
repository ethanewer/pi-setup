#!/usr/bin/env bash
# Sample 10 of the 54 tasks that no harness/model pair ever scored 1.0 on and
# that have never been oracle-swept. Three of the five partial-credit tasks in
# that same never-passed group turned out to be genuine task defects, so the
# question is how many of these 54 are broken rather than merely hard.
#
# Oracle agent: no model, no LLM inference. Low concurrency so it does not
# contend with the two v1-item-043-hard rollout trials still running, which are
# CPU-bound MCMC and already at their budget.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
export PYTHONPATH=$EVAL/agents
cd "$EVAL"

echo "[sample] $(date -Is) START"
"$HARBOR" run -p /home/ee/general-eval-runs/v33-tasks/oracle-sample -n 2 -k 1 -y -q \
  --job-name v33-oracle-sample -o "$OUT" -a oracle \
  > "$OUT/v33-oracle-sample.harness.log" 2>&1
echo "[sample] $(date -Is) DONE rc=$?"

python3 - <<'PY'
import json
from pathlib import Path
job = Path('/home/ee/general-eval-runs/jobs/v33-oracle-sample')
want = {p.name for p in Path('/home/ee/general-eval-runs/v33-tasks/oracle-sample').iterdir()}
seen, passed, failed, noreward = {}, [], [], []
for rp in sorted(job.glob('*__*/result.json')):
    td = rp.parent
    task = td.name.split('__')[0]
    try:
        res = json.loads(rp.read_text())
    except Exception:
        continue
    exc = (res.get('exception_info') or {}).get('exception_type')
    rwp = td / 'verifier/reward.txt'
    if not rwp.exists():
        noreward.append((task, exc)); seen[task] = None; continue
    raw = rwp.read_text().strip()
    try:
        val = float(raw.splitlines()[-1]) if raw else None
    except ValueError:
        val = None
    seen[task] = val
    (passed if val == 1.0 else failed).append((task, raw, exc))
print(f'ORACLE_SAMPLE seen={len(seen)}/{len(want)} oracle_pass={len(passed)} '
      f'oracle_FAIL={len(failed)} no_reward={len(noreward)}')
for t, raw, exc in failed:
    print(f'  BROKEN? {t:24s} oracle_reward={raw!r} exception={exc}')
for t, exc in noreward:
    print(f'  NO_REWARD {t:22s} exception={exc}')
for t in sorted(want - set(seen)):
    print(f'  NO_TRIAL {t}')
print('ORACLE_SAMPLE_FINISHED')
PY
