#!/bin/bash
set -euo pipefail
cd /app/repo
git filter-branch --force --index-filter 'git rm -r --cached --ignore-unmatch secret.txt' --prune-empty -- --all
# drop the working-tree copy and any backup refs pointing at the old history
rm -f secret.txt
git update-ref -d refs/original/refs/heads/main 2>/dev/null || true
git reflog expire --expire=now --all 2>/dev/null || true
git gc -q || true