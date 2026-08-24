#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/repo.bundle ]; then
  header=$(head -c 16 /app/repo.bundle 2>/dev/null | tr -d '\r\n')
  if [ "$header" = "# v2 git bundle" ]; then
    rm -rf /tmp/restore
    if git clone /app/repo.bundle /tmp/restore >/dev/null 2>&1; then
      content=$(cat /tmp/restore/data.txt 2>/dev/null | tr -d '\r\n')
      if [ "$content" = "omega" ]; then
        reward=1
      fi
    fi
  fi
fi
rm -rf /tmp/restore
echo "$reward" > /logs/verifier/reward.txt