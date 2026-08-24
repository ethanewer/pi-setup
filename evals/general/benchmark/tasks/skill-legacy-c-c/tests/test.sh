#!/bin/bash
mkdir -p /logs/verifier
reward=0
# verifier recompiles the agent's fixed file and checks output
if [ -f /app/legacy.c ] && [ -f /app/run_output.txt ]; then
  if gcc /app/legacy.c -o /tmp/legacy_check 2>/tmp/gcc_err.txt; then
    line=""
    line=$(/tmp/legacy_check 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
    got=$(sed 's/[[:space:]]*$//' /app/run_output.txt)
    if [ "$line" = "c=A i=10" ] && [ "$got" = "c=A i=10" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt