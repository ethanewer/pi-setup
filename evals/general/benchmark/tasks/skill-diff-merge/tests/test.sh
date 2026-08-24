#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/merged.txt ]; then
  expected=$(printf 'alpha\nONE\ntwo\nTHREE\nomega\n')
  if [ "$(cat /app/merged.txt)" = "$expected" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt