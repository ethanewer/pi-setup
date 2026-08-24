#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/report.pdf ]; then
  size=$(stat -c '%s' /app/report.pdf 2>/dev/null || echo '0')
  magic=$(head -c 5 /app/report.pdf 2>/dev/null)
  if [ "$magic" = "%PDF-" ] && [ "$size" -gt 2000 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt