#!/usr/bin/env bash
# Verifier for arid-jetty. Executes every deliverable: imports /app/solve.py and
# re-runs each behavioral probe (wasm offset/byte, closures/currying/mutual
# recursion, hash<=>equality, imported iteration constant, Vimscript layout
# replay), checks /app/answer.json and /app/recreate.vim consistency, then runs
# the hidden cases under /tests/hidden (edge + malformed + value-override).
# reward.txt = 1 only if every check passes.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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