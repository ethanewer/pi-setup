#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

granted=0
if [ -f /app/payload ] && /app/vuln < /app/payload 2>/dev/null | grep -q 'ACCESS GRANTED'; then
  granted=1
fi

safe_denies=0
if [ -f /app/safe.c ]; then
  if gcc -O0 -o /tmp/safe /app/safe.c 2>/tmp/gcc.log && ! /tmp/safe < /app/payload 2>/dev/null | grep -q 'ACCESS GRANTED'; then
    safe_denies=1
  fi
fi

explained=0
if [ -f /app/explanation.txt ]; then
  if grep -qi 'overflow' /app/explanation.txt; then
    explained=1
  fi
fi

reward=0
if [ "$granted" = 1 ] && [ "$safe_denies" = 1 ]; then
  reward=1
elif [ "$granted" = 1 ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
