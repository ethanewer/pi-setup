#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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