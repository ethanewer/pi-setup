#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/solver.py ] && [ -f /app/talker.py ]; then
  start_ns=$(date +%s%N)
  out=$(python3 /app/solver.py 2>/dev/null)
  end_ns=$(date +%s%N)
  elapsed_ms=$(((end_ns - start_ns) / 1000000))
  has_alpha=0; has_beta=0; used_async=0; concurrent_ok=0
  echo "$out" | grep -q "hello from alpha" && has_alpha=1
  echo "$out" | grep -q "hello from beta" && has_beta=1
  grep -q "create_subprocess" /app/solver.py && used_async=1
  # concurrency: two 0.6s sleeps finish in ~0.6s of wall time, not ~1.2s
  if [ "$elapsed_ms" -lt 1100 ]; then concurrent_ok=1; fi
  if [ "$has_alpha$has_beta$used_async$concurrent_ok" = "1111" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt