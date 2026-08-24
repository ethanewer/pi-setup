#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
EXP=$(git -C /app/work rev-list main --grep 'feature X' -1 2>/dev/null)
if [ -n "$EXP" ]; then
  LOCAL=$(git -C /app/work rev-parse refs/heads/hotfix 2>/dev/null || true)
  REMOTE=$(git -C /app/src.git rev-parse refs/heads/hotfix 2>/dev/null || true)
  REMOTE_TAG=$(git -C /app/src.git rev-parse refs/tags/v1.0 2>/dev/null || true)
  CLEAN=$(git -C /app/work status --porcelain 2>/dev/null || true)
  if [ "$LOCAL" = "$EXP" ] && [ "$REMOTE" = "$EXP" ] && [ "$REMOTE_TAG" = "$EXP" ] && [ -z "$CLEAN" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
