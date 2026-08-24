#!/bin/bash

reward=0
if [ -f /app/sites.txt ]; then
  got=$(cat /app/sites.txt)
  if [ "$got" = "1:[foo]"$'\n'"2:[bar]"$'\n'"3:[baz]" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt