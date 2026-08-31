#!/bin/bash
# Verifier entrypoint for marl-haven (executes-deliverable). Runs the checker
# and always leaves a numeric reward at /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 /tests/check.py
rc=$?
if [ ! -f /logs/verifier/reward.txt ]; then
  if [ $rc -eq 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
fi
exit 0
