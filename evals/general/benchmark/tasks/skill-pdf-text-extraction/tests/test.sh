#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/extracted.txt ] && [ -f /app/doc.pdf ]; then
  got=$(sed -e 's/[[:space:]]*$//' /app/extracted.txt)
  if [ "$got" = "The quick brown fox jumps over the lazy dog." ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt