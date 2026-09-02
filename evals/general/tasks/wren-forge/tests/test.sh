#!/bin/bash
# Verifier for wren-forge: EXECUTES the deliverable driver (/app/fit.R) on the
# visible fixture and on hidden trial tables, independently re-compiles the
# deliverable Stan program (/app/hier_model.stan) and samples it, and checks
# posterior semantics against the empirical germination rates. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on bad agent output.
set -u
mkdir -p /logs/verifier

reward=0

PRISTINE_TRIALS_SHA="ffd751502ebd40897c7e6df7fd3fc0f77e6bec08ce8808bda6dde348e7bc91fe"
if [ -f /app/trials.csv ]; then
  actual="$(sha256sum /app/trials.csv | awk '{print $1}')"
  if [ "$actual" != "$PRISTINE_TRIALS_SHA" ]; then
    echo "no-modify: /app/trials.csv was modified" >&2
    echo 0 > /logs/verifier/reward.txt
    exit 0
  fi
else
  echo "no-modify: /app/trials.csv missing" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

for f in /app/fit.R /app/hier_model.stan /app/posterior.csv /app/summary.json; do
  if [ ! -f "$f" ]; then
    echo "missing deliverable $f" >&2
    echo 0 > /logs/verifier/reward.txt
    exit 0
  fi
done

Rscript /tests/verify.R
rc=$?
if [ "$rc" -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
