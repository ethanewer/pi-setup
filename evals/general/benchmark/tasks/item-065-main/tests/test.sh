#!/bin/bash
# item-065-main verifier entry point.
mkdir -p /logs/verifier
reward=0.0

python3 /tests/test_roundtrip.py > /tmp/rt.log 2>&1
rw=$(grep -o 'REWARD=[0-9.]*' /tmp/rt.log | head -1 | cut -d= -f2)
if [ -n "$rw" ]; then
  echo "$rw" > /logs/verifier/reward.txt
else
  echo "$reward" > /logs/verifier/reward.txt
fi
exit 0