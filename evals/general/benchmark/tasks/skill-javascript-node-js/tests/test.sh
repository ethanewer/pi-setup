#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=$(python3 -c "
import functools
nums=[int(l) for l in open('/app/numbers.txt') if l.strip()]
print(functools.reduce(lambda a,b:a*b, nums, 1))
" 2>/dev/null)
if [ -n "$exp" ] && [ -f /app/product_output.txt ]; then
  got=$(python3 -c "print(open('/app/product_output.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt