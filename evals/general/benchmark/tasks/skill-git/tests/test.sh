#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -d /app/repo/.git ] && [ -f /app/repo/greeting.txt ]; then
  content=$(cat /app/repo/greeting.txt | tr -d '\r\n')
  cnt=$(git -C /app/repo rev-list --count HEAD 2>/dev/null)
  subj=$(git -C /app/repo log -1 --pretty=%s 2>/dev/null)
  if [ "$content" = "harbor-git-probe" ] && [ "$cnt" = "1" ] && [ "$subj" = "add greeting" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt