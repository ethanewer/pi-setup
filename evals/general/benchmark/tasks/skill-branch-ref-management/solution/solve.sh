#!/usr/bin/env bash
set -euo pipefail
export GIT_AUTHOR_NAME=bench GIT_AUTHOR_EMAIL=b@e.io
export GIT_COMMITTER_NAME=bench GIT_COMMITTER_EMAIL=b@e.io

cd /app/work
FEATURE_TARGET=$(git rev-list main --grep 'feature X' -1)

# 1. branch from the "add feature X" commit
git checkout -q -b hotfix "$FEATURE_TARGET"

# 2. push the branch
git push -q origin hotfix

# 3. lightweight tag at hotfix tip and push it
git tag v1.0
git push -q origin v1.0

# 4. clean worktree
git checkout -q main
test -z "$(git status --porcelain)"
