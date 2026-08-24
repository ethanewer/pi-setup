#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
expected=338350  # sum of squares 1..100 = n(n+1)(2n+1)/6
if [ -f "$APP/result.txt" ]; then
  got=$(cat "$APP/result.txt")
  if [ "$got" = "$expected" ]; then
    if ls "$APP"/math/fastmath*.so >/dev/null 2>&1; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt