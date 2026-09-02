#!/bin/bash
set -euo pipefail
cd /app/repo
git log --oneline --all
git tag
git checkout -q v2
printf '%s' "$(cat version.txt)" > /app/answer.txt