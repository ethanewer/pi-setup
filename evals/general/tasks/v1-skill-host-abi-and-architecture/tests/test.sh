#!/bin/bash
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