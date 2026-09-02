#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -d /app/pulled/.git ]; then
  content=$(cat /app/pulled/README.txt 2>/dev/null | tr -d '\r\n')
  url=$(git -C /app/pulled remote get-url origin 2>/dev/null)
  if [ "$content" = "ssh-hello" ]; then
    # origin must be an SSH transport URL (ssh:// or user@host:path)
    if echo "$url" | grep -qE "ssh://|@127\.0\.0\.1|sshgit@"; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt