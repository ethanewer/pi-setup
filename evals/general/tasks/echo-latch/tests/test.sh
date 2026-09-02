#!/bin/bash
# echo-latch verifier. Executes the /app/reclaim_fd.py deliverable against the
# live visible keeper and against fresh hidden keeper processes with different
# payloads, pidfile locations, and decoys. Writes /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
