#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/test_xss_regression.py ]; then
  if python3 -m pytest /app/test_xss_regression.py -q >/dev/null 2>&1; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
