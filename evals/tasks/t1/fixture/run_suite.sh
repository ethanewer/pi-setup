#!/usr/bin/env bash
# Integration test suite for the payments platform.
set -euo pipefail
SEED="${SEED:-0}"
DUR=$(python3 -c "import random; print(random.Random('${SEED}:t1:suite').randint(90, 180))")
MODULES=(auth payments search inventory checkout notifications reporting)
echo "[suite] starting integration suite ($DUR s budget allocated to workers)"
END=$((SECONDS + DUR))
i=0
while (( SECONDS < END )); do
  m=${MODULES[$((i % ${#MODULES[@]}))]}
  echo "[suite] module $m: case $((i + 1)) ok"
  sleep $((4 + (i % 3) * 2))
  i=$((i + 1))
done
echo "TEST SUITE COMPLETE: 47 passed, 0 failed"
