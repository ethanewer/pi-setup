#!/bin/bash

# Verifier for item-023-main.  Must always write /logs/verifier/reward.txt
mkdir -p /logs/verifier
reward=0

if [ -f /app/app/commands.txt ]; then
  if python3 /tests/check_023.py; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt