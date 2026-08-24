#!/bin/bash
mkdir -p /logs/verifier
reward=0

expected="test1.txt sports
test2.txt finance
test3.txt tech"

if [ -f /app/predictions.txt ]; then
  if [ "$(cat /app/predictions.txt)" = "$expected" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt