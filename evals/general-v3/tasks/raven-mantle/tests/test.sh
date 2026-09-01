#!/bin/bash
# Verifier entrypoint for raven-mantle (executes-deliverable).
# Runs every /app/infer.py mode on the default fixtures and all hidden
# scenarios, checks engine byte integrity, and writes the reward.
set -u
mkdir -p /logs/verifier
mkdir -p /tmp/jobs

if [ ! -f /app/infer.py ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/loss.txt ] || [ ! -f /app/batch_plan.json ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 /tests/check.py /tests/hidden/caseAlt /tests/hidden/caseEdge /tests/hidden/caseMass

if [ ! -f /logs/verifier/reward.txt ]; then
  echo "0" > /logs/verifier/reward.txt
fi
exit 0