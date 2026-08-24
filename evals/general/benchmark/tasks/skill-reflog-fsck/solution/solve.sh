#!/usr/bin/env bash
set -euo pipefail
# Recover the golden-secret commit sha and write to /app/agent.txt
for entry in $(git -C /app/repo cat-file --batch-all-objects --batch-check 2>/dev/null); do
  obj=$(echo "$entry" | cut -d' ' -f1)
  if [ -z "$obj" ]; then
    continue
  fi
  subj=$(git -C /app/repo show -s --format=%s "$obj" 2>/dev/null || true)
  if [ "$subj" = "golden-secret" ]; then
    echo "$obj" > /app/agent.txt
    echo "found $obj"
    exit 0
  fi
done
echo "NOT FOUND" > /app/agent.txt
exit 1