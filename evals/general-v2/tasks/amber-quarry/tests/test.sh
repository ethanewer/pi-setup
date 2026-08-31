#!/bin/bash
# amber-quarry verifier. Runs as root after the agent finishes. Executes the
# deliverable (/app/mirror.py) on the visible case's fixed inputs and on
# seeded random inputs, compares to an onnxruntime reference within tolerance,
# validates /app/answer.npz, then replays on every hidden fixture.
# Writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
REWARD=0
reason=""

for f in /app/mirror.py /app/answer.npz; do
  [ -f "$f" ] || { reason="$reason missing-$f"; }
done

if [ -z "$reason" ]; then
  if ! python3 /tests/verify.py /app/case /app/answer.npz >/tmp/vis.log 2>&1; then
    reason="visible-verify-failed"
    sed -n '1,30p' /tmp/vis.log
  fi
fi

if [ -z "$reason" ]; then
  for d in /tests/hidden/*/; do
    name=$(basename "$d")
    if ! python3 /tests/verify.py "$d" - >"/tmp/h_$name.log" 2>&1; then
      reason="$reason hidden-$name-failed"
      sed -n '1,30p' "/tmp/h_$name.log"
    fi
  done
fi

if [ -z "$reason" ]; then
  REWARD=1
fi

echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD reason=${reason:-ok}"
exit 0
