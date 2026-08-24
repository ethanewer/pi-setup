#!/bin/bash
set -euo pipefail
mkdir -p /app/repo
cd /app/repo
git init -q
git config user.email "harbor@example.com"
git config user.name "Harbor Agent"
printf 'harbor-git-probe\n' > greeting.txt
git add greeting.txt
git commit -q -m "add greeting"