#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -d /app/harbor.git ]; then
  rm -rf /tmp/verify_clone
  if git clone /app/harbor.git /tmp/verify_clone >/dev/null 2>&1; then
    content=$(cat /tmp/verify_clone/README.md 2>/dev/null)
    if [ "$content" == "harbor-bare-repository" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
