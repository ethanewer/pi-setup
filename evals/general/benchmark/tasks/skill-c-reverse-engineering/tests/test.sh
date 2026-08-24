#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/flag.txt ]; then
  flag=$(cat /app/flag.txt | tr -d '\r')
  # independent oracle: run the binary with the correct decoded password "r3v3rs3_m3"
  expected=$(/app/chal r3v3rs3_m3 2>/dev/null)
  if [ -n "$expected" ] && [ "$flag" = "$expected" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt