#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=""
if [ -f /app/number.txt ]; then
  n=$(python3 -c "import sys; print(int(open('/app/number.txt').read().strip()))" 2>/dev/null)
  if [ -n "$n" ]; then
    exp=$(python3 -c "import math,sys; print(math.isqrt(int(sys.argv[1])))" "$n" 2>/dev/null)
  fi
fi
if [ -n "$exp" ] && [ -f /app/sqrt_output.txt ]; then
  got=$(python3 -c "print(open('/app/sqrt_output.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt