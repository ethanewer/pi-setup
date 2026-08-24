#!/bin/bash
set -euo pipefail
cd /app
rm -rf developer /tmp/verify_clone
git clone /app/team.git /app/developer
cd /app/developer
git config user.email "harbor@example.com"
git config user.name "Harbor"
printf 'team-bare-notes\n' > notes.txt
git add notes.txt
git commit -q -m "add notes"
branch=$(git branch --show-current)
git push -u origin "$branch"