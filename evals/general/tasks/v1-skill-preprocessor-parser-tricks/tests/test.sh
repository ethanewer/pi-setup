#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0

if [ -f "$APP/tricks.c" ] && [ -f "$APP/out.txt" ]; then
  if grep -q '##' "$APP/tricks.c" 2>/dev/null; then
    rm -f /tmp/tricks_built
    if gcc -o /tmp/tricks_built "$APP/tricks.c" 2>/dev/null; then
      out=$(/tmp/tricks_built 2>/dev/null | tr -d '\r\n')
      saved=$(cat "$APP/out.txt" 2>/dev/null | tr -d '\r\n')
      if [ "$out" = "1 hello" ] && [ "$saved" = "1 hello" ]; then
        reward=1
      fi
    fi
  fi
fi
printf '%s' "$reward" > /logs/verifier/reward.txt