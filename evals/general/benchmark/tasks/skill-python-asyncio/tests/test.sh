#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/solver.py ] && [ -f /app/answer.txt ]; then
  start_ns=$(date +%s%N)
  out=$(python3 /app/solver.py 2>/dev/null)
  rc=$?
  end_ns=$(date +%s%N)
  elapsed_ms=$(((end_ns - start_ns) / 1000000))
  content_ok=0
  concurrent_ok=0
  if [ "$rc" -eq 0 ]; then
    got=$(sed -e 's/[[:space:]]*$//' /app/answer.txt)
    [ "$got" = "total squares = 52" ] && content_ok=1
  fi
  # two 0.5s sleeps run concurrently -> ~0.5s, not ~1.0s
  if [ "$elapsed_ms" -lt 950 ]; then concurrent_ok=1; fi
  if [ "$content_ok" = "1" ] && [ "$concurrent_ok" = "1" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt