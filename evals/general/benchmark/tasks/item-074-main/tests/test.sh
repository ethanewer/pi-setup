#!/bin/bash

# Verifier for item-074-main. Must always write /logs/verifier/reward.txt.
mkdir -p /logs/verifier

if [ -f /app/events.json ]; then
  reward=$(python3 /tests/check_074_main.py 2>/dev/null || echo 0)
else
  reward=0
fi

case "$reward" in
  ""|*[!0-9.]*) reward=0 ;;
esac

echo "$reward" > /logs/verifier/reward.txt