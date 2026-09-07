#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
mkdir -p /logs/verifier
if [ -f /app/host/probe.c ]; then
  if gcc -O2 -o /tmp/probe /app/host/probe.c 2>/dev/null; then
    expected=$(/tmp/probe)
    if [ -f /app/host/abi.txt ]; then
      got=$(cat /app/host/abi.txt)
      if [ "$got" == "$expected" ]; then
        reward=1
      fi
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt