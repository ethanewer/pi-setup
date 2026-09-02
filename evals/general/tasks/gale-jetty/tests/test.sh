#!/bin/bash
# Verifier entrypoint for gale-jetty (executes-deliverable).
# Re-invokes /app/reconcile.py on the visible fixtures and all hidden cases,
# independently re-derives expected results from the raw fixtures, and writes a
# numeric reward to /logs/verifier/reward.txt. It must always leave a reward.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/reconcile.py ]; then
  echo "missing deliverable /app/reconcile.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 /tests/check.py
if [ ! -f /logs/verifier/reward.txt ]; then
  echo "0" > /logs/verifier/reward.txt
fi
exit 0
