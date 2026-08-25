#!/bin/bash
# Verifier for item-043-main: reruns the agent's fit scripts and scores them.
# Always writes /logs/verifier/reward.txt.
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
      /app/rstan_diag.json /app/pystan_diag.json > /tmp/cross.json 2>&1; then
    reward=1
  else
    reward=0.6   # both fit, but diagnostics/agreement not met
    echo "evaluate_043 failed:" >&2
    cat /tmp/cross.json >&2
  fi
elif [ "$r_ran" = "1" ] || [ "$p_ran" = "1" ]; then
  reward=0.3
fi

echo "$reward" > /logs/verifier/reward.txt