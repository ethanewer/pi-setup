#!/usr/bin/env bash
set -euo pipefail
export GIT_AUTHOR_NAME=bench GIT_AUTHOR_EMAIL=b@e.io
export GIT_COMMITTER_NAME=bench GIT_COMMITTER_EMAIL=b@e.io

cd /app/workflow
GOOD=$(git rev-list feature --grep 'add util module' -1)
TESTC=$(git rev-list feature --grep 'add util tests' -1)

# 1. drop the WIP experiment, keep the tests
git checkout -q feature
git reset -q --hard "$GOOD"
git cherry-pick "$TESTC"

# 2. discard the uncommitted TODO edit
git checkout -q main
git reset -q --hard HEAD

# 3. merge with a real merge commit
git merge --no-ff feature -m "merge feature into main"

# 4. clean worktree
test -z "$(git status --porcelain)"
