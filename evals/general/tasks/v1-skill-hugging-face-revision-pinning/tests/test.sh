#!/bin/bash
reward=0
mkdir -p /logs/verifier
cd /app/repo 2>/dev/null || { echo "$reward" > /logs/verifier/reward.txt; exit 0; }
git checkout -q v2 2>/dev/null
expected=$(cat version.txt 2>/dev/null)
got=$(cat /app/answer.txt 2>/dev/null)
if [ -n "$expected" ] && [ "$got" == "$expected" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt