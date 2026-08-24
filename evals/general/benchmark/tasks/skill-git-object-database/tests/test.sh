#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/repo/seed/input.txt ] && [ -f /app/answer.txt ]; then
  exp=$(git hash-object /app/repo/seed/input.txt 2>/dev/null)
  got=$(cat /app/answer.txt | tr -d ' \r\n\t' | tr 'A-F' 'a-f')
  if [ -n "$exp" ] && [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt