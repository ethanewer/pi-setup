#!/usr/bin/env bash
# Oracle sweep over the 45 verifiers that were binarized for the reward contract.
# Runs each task's own solution/solve.sh through harbor's oracle agent (no model,
# no LLM inference) and checks the verifier still awards exactly 1.
#
# This closes the gap WORKFLOW.md records: the binarization is safe by
# construction, but "safe by construction" is not the same as "the reference
# solution still passes". Concurrency is kept low so it does not contend with the
# live v3.3 re-run rollouts.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v33-tasks/oracle
export PYTHONPATH=$EVAL/agents
cd "$EVAL"

n=$(find "$SET" -mindepth 1 -maxdepth 1 | wc -l)
echo "[oracle] $(date -Is) START $n tasks"
"$HARBOR" run \
  -p "$SET" \
  -n 6 -k 1 -y -q \
  --job-name v33-oracle-binarized -o "$OUT" \
  -a oracle \
  > "$OUT/v33-oracle-binarized.harness.log" 2>&1
rc=$?
echo "[oracle] $(date -Is) DONE rc=$rc"

python3 - "$OUT/v33-oracle-binarized" <<'PY'
import json, sys
from pathlib import Path
job = Path(sys.argv[1])
ok, bad, noreward, notrial = [], [], [], []
seen = set()
for rp in sorted(job.glob('*__*/result.json')):
    td = rp.parent
    task = td.name.split('__')[0]
    seen.add(task)
    try:
        res = json.loads(rp.read_text())
    except Exception as e:
        bad.append((task, f'result.json unparseable: {e}'))
        continue
    exc = (res.get('exception_info') or {}).get('exception_type')
    rwp = td / 'verifier/reward.txt'
    if not rwp.exists():
        noreward.append((task, f'no reward.txt (exception={exc})'))
        continue
    raw = rwp.read_text().strip()
    try:
        val = float(raw.splitlines()[-1]) if raw else None
    except ValueError:
        val = None
    if val != 1.0:
        bad.append((task, f'reward={raw!r} (exception={exc})'))
    else:
        ok.append(task)
expected = {p.name for p in Path('/home/ee/general-eval-runs/v33-tasks/oracle').iterdir()}
missing = sorted(expected - seen)
print(f'ORACLE_SWEEP trials_seen={len(seen)} expected={len(expected)} '
      f'reward_1={len(ok)} not_1={len(bad)} no_reward={len(noreward)} no_trial={len(missing)}')
for t, why in bad:
    print(f'  FAIL {t}: {why}')
for t, why in noreward:
    print(f'  NO_REWARD {t}: {why}')
for t in missing:
    print(f'  NO_TRIAL {t}')
print('ORACLE_SWEEP_RESULT ' + ('PASS' if not (bad or noreward or missing) else 'FAIL'))
PY
