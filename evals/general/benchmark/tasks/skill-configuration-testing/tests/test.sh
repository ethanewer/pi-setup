#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/testresult.txt" ]; then
  if [ "$(cat "$APP/testresult.txt")" = "ALL_CONFIG_TESTS_PASS" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt