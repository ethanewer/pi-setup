#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=$(python3 -c "import json; print(json.load(open('/app/config.json'))['server']['port'])" 2>/dev/null)
if [ -n "$exp" ] && [ -f /app/port_output.txt ]; then
  got=$(python3 -c "print(open('/app/port_output.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt