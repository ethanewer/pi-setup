#!/bin/bash
# Verifier for item-004-main.
set -u
mkdir -p /logs/verifier

rm -f /logs/verifier/reward.txt
python3 /tests/test_check.py
if [ -f /logs/verifier/reward.txt ]; then
  chmod 755 /logs 2>/dev/null
else
  echo "0" > /logs/verifier/reward.txt
fi
exit 0