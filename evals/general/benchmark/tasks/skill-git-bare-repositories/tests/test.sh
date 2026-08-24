#!/bin/bash
mkdir -p /logs/verifier
reward=0
bare=$(git --git-dir=/app/team.git rev-parse --is-bare-repository 2>/dev/null)
rm -rf /tmp/verify_clone
if [ "$bare" = "true" ] && git clone /app/team.git /tmp/verify_clone >/dev/null 2>&1; then
  content=$(cat /tmp/verify_clone/notes.txt 2>/dev/null | tr -d '\r\n')
  cnt=$(git -C /tmp/verify_clone rev-list --count HEAD 2>/dev/null)
  if [ "$content" = "team-bare-notes" ] && [ "$cnt" = "1" ]; then
    reward=1
  fi
fi
rm -rf /tmp/verify_clone
echo "$reward" > /logs/verifier/reward.txt