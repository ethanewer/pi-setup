#!/bin/bash
set -euo pipefail
cd /app
rm -rf harbor.git dev
git init --bare harbor.git
mkdir dev
cd dev
git init
git config user.email harbor@example.com
git config user.name "Harbor Agent"
git branch -M main
echo "harbor-bare-repository" > README.md
git add README.md
git commit -m "init harbor bare repo"
git remote add origin /app/harbor.git
git push -u origin main
# Point the bare repo HEAD at the pushed branch so clones check it out.
git --git-dir=/app/harbor.git symbolic-ref HEAD refs/heads/main
