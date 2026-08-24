#!/bin/bash
mkdir -p /logs/verifier

reward=0
cd /app/repo 2>/dev/null || { echo "$reward" > /logs/verifier/reward.txt; exit 0; }

# 1) conflict markers gone and required content present
content_ok=0
if [ -f config.txt ]; then
  if [ "$(cat config.txt | tr -d '\r')" = 'resolution=durable' ]; then
    content_ok=1
  fi
fi

# 2) HEAD is a merge commit: rev^2 resolves
merge_ok=0
if git rev-parse --quiet HEAD^2 >/dev/null 2>&1; then
  merge_ok=1
fi

# 3) working tree clean (no unmerged/uncommitted/untracked paths)
status_ok=0
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  status_ok=1
fi

if [ "$content_ok" = 1 ] && [ "$merge_ok" = 1 ] && [ "$status_ok" = 1 ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt