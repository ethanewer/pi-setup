#!/bin/bash

reward=0
if [ -f /app/recovered.txt ]; then
  got=$(cat /app/recovered.txt)
  if [ "$got" = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt