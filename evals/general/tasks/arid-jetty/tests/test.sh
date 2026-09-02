#!/usr/bin/env bash
# Verifier for arid-jetty. Executes every deliverable: imports /app/solve.py and
# re-runs each behavioral probe (wasm offset/byte, closures/currying/mutual
# recursion, hash<=>equality, imported iteration constant, Vimscript layout
# replay), checks /app/answer.json and /app/recreate.vim consistency, then runs
# the hidden cases under /tests/hidden (edge + malformed + value-override).
# reward.txt = 1 only if every check passes.
set -u
mkdir -p /logs/verifier
reward=0
cd /app
if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0