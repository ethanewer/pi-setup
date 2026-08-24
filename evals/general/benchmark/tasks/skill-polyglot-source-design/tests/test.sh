#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/polyglot" ]; then
  o1=$(python3 "$APP/polyglot" 2>/dev/null | tr -d '\r\n')
  o2=$(bash "$APP/polyglot" 2>/dev/null | tr -d '\r\n')
  if [ "$o1" = "42" ] && [ "$o2" = "42" ]; then
    reward=1
  fi
fi
printf '%s' "$reward" > /logs/verifier/reward.txt