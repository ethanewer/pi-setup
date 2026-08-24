#!/bin/bash

# Verifier for item-022-main.
# Runs after the agent finishes; must always write /logs/verifier/reward.txt

mkdir -p /logs/verifier
reward=0

if [ -f /app/elf.json ] && [ -s /app/elf.json ]; then
  if python3 /tests/check_022.py; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt