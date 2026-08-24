#!/bin/bash
# Verifier for item-010-hard.
mkdir -p /logs/verifier
if [ -f /app/sqrt_32.ng ] && [ -f /app/fib_64.ng ]; then
  python3 /tests/test.py
else
  echo 0 > /logs/verifier/reward.txt
fi