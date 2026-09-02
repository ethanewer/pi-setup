#!/bin/bash
reward=0
ok=1
[ ! -f /tmp/worker_ready ] && ok=0
[ ! -f /tmp/worker_result.txt ] && ok=0
[ ! -f /app/result.txt ] && ok=0
if [ "$ok" == "1" ]; then
  exp=$(cat /tmp/worker_result.txt 2>/dev/null)
  got=$(cat /app/result.txt 2>/dev/null)
  if [ "$exp" != "$got" ] || [ -z "$exp" ]; then ok=0; fi
fi
if [ "$ok" == "1" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
