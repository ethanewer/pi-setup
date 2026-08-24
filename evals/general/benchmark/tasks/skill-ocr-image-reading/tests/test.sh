#!/bin/bash
# Verifier for skill-ocr-image-reading: id.txt must contain the digits 0183.
mkdir -p /logs/verifier
reward=0

if [ -f /app/id.txt ]; then
  digits=$(tr -cd '0-9' < /app/id.txt)
  if [ "$digits" = "0183" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0