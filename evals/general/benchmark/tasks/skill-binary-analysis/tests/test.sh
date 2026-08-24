#!/bin/bash
reward=0
if [ -f /app/found.txt ]; then
  got=$(cat /app/found.txt | tr -d ' \r\n')
  if [ "$got" == "T0ken-Xc7QpR9" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
