#!/bin/bash
# Oracle solution for item-044: reconstruct the git repo from the bundle and
# apply only the legitimate fix commit. Deterministic; runs offline.
#
# feature/fix carries two commits on top of main: the legitimate
# `fix: correct rotate outputs in 1e0a9b12` and, as the branch tip, the unwanted
# `chore: drop 3ccc3b22 and annotate byou6dgf`. So the fix is feature/fix~1.
set -euo pipefail

rm -rf /app/arc-repo
git clone -q /app/arc-repo.bundle /app/arc-repo || { echo "clone failed"; exit 1; }
cd /app/arc-repo

# The container has no committer identity. Without this, `git cherry-pick`
# applies the change to the index and worktree and then dies with rc=128
# "Committer identity unknown", leaving the fix staged but uncommitted: the file
# content is right, `git status --porcelain` is not empty, and the verifier's
# branch/clean-tree check fails while every content check passes. Agents hit the
# same wall and configured identity themselves, which is why all six scored 1
# while this oracle scored 6/7.
git config user.email "oracle@general-agent-bench.invalid"
git config user.name "Oracle Solution"

FIX_REF="$(git rev-parse origin/feature/fix~1)"
git cherry-pick "$FIX_REF"

# sanity: main, clean tree, wanted files, no corrupt file
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 1
[ -z "$(git status --porcelain)" ] || exit 1
[ -f tasks/1e0a9b12.json ] || exit 1
[ -f tasks/byou6dgf.json ] || exit 1
[ -f tasks/3ccc3b22.json ] || exit 1
[ ! -f tasks/9e9ff3c4.json ] || exit 1

# the only difference from origin/main must be the fixed file
[ "$(git diff --name-only origin/main)" = "tasks/1e0a9b12.json" ] || exit 1
echo "oracle: main clean, fix committed as $(git rev-parse --short HEAD)"
