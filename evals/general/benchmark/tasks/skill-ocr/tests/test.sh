#!/bin/bash
# Verifier for skill-ocr: normalized agent text must equal "HARBOR42".
mkdir -p /logs/verifier
reward=0

if [ -f /app/read.txt ]; then
  norm=$(tr 'a-z' 'A-Z' < /app/read.txt | tr -cd 'A-Z0-9')
  if [ "$norm" = "HARBOR42" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0