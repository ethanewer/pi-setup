#!/bin/bash
# Verifier for item-066-hard. Always writes a numeric reward.
mkdir -p /logs/verifier

reward=0
if [ -f /app/out/annotations.json ]; then
  out=$(python3 /tests/test_check2.py 2>/dev/null | tail -1)
  case "$out" in
    REWARD*) reward=${out#REWARD } ;;
  esac
fi

re='^[0-9]+([.][0-9]+)?$'
if ! [[ "$reward" =~ $re ]]; then
  reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0