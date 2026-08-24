#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/archive.7z ] && [ -f /app/secret_out.txt ]; then
  # independently extract the archive to derive the expected value
  rm -rf /tmp/vx
  mkdir -p /tmp/vx
  if 7z e -o/tmp/vx /app/archive.7z >/dev/null 2>&1; then
    expected=""
    for f in /tmp/vx/*; do
      if [ -f "$f" ]; then expected=$(sed -e 's/[[:space:]]*$//' "$f"); break; fi
    done
    got=$(sed -e 's/[[:space:]]*$//' /app/secret_out.txt)
    if [ -n "$expected" ] && [ "$got" = "$expected" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt