#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=$(python3 -c "print(sum(int(l.strip()) for l in open('/app/numbers.txt') if l.strip()))" 2>/dev/null)
if [ -n "$exp" ] && [ -f /app/sum_output.txt ]; then
  got=$(python3 -c "print(open('/app/sum_output.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt