#!/bin/bash

reward=0
if gcc -o /app/ub /app/ub.c >/tmp/gcc.log 2>&1; then
  o1=$(/app/ub)
  o2=$(/app/ub)
  if [ "$o1" = "total=6" ] && [ "$o2" = "total=6" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt