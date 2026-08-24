#!/bin/bash
# Verifier for item-043-hard: rerun both scripts (agent-fixed RStan script +
# PyStan script), strict gates, posterior predictive sanity.
set -uo pipefail
cd /app
mkdir -p /logs/verifier

Rscript /app/fit_rstan.R > /tmp/fit_r.out 2>&1; rc_r=$?
python3 /app/fit_pystan.py > /tmp/fit_p.out 2>&1; rc_p=$?

r_ran=0; p_ran=0
[ "$rc_r" = "0" ] && [ -s /app/rstan_summary.csv ] && [ -s /app/rstan_diag.json ] && r_ran=1
[ "$rc_p" = "0" ] && [ -s /app/pystan_summary.csv ] && [ -s /app/pystan_diag.json ] && p_ran=1

reward=0
if [ "$r_ran" = "1" ] && [ "$p_ran" = "1" ]; then
  if python3 /tests/evaluate_043.py /app/rstan_summary.csv /app/pystan_summary.csv \
      /app/rstan_diag.json /app/pystan_diag.json --hard > /tmp/cross.json 2>&1; then
    reward=1
  else
    reward=0.6
  fi
elif [ "$r_ran" = "1" ] || [ "$p_ran" = "1" ]; then
  reward=0.3
fi

# posterior predictive sanity: requires /app/ppc.json with ratios in range
ppc_ok=0
if [ -s /app/ppc.json ]; then
  python3 - <<'PY' && ppc_ok=1
import json
p = json.load(open("/app/ppc.json"))
mr = p["mean_y_rep"] / p["mean_y"] if p["mean_y"] != 0 else 1
sr = p["sd_y_rep"] / p["sd_y"] if p["sd_y"] != 0 else 1
ok = (0.75 <= mr <= 1.25) and (0.5 <= sr <= 2.0)
print(json.dumps({"mean_ratio": mr, "sd_ratio": sr, "ok": ok}))
exit(0 if ok else 1)
PY
fi
if [ "$ppc_ok" = "1" ] && [ "$reward" = "1" ]; then reward=1
elif [ "$reward" = "1" ]; then reward=0.6
fi

echo "$reward" > /logs/verifier/reward.txt