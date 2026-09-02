#!/bin/bash
# Oracle solution for item-044: reconstruct the git repo from the bundle and
# apply only the legitimate fix commit. Deterministic; runs offline.
set -euo pipefail

rm -rf /app/arc-repo
git clone -q /app/arc-repo.bundle /app/arc-repo || { echo "clone failed"; exit 1; }
cd /app/arc-repo

FIX_REF="$(git rev-parse origin/feature/fix~1)"
git cherry-pick "$FIX_REF"
git commit -q --amend --no-edit --author="T <a@b.c>" 2>/dev/null || true

# sanity: main, clean tree, wanted files, no corrupt file
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 1
[ -z "$(git status --porcelain)" ] || exit 1
[ -f tasks/1e0a9b12.json ] || exit 1
[ -f tasks/byou6dgf.json ] || exit 1
[ -f tasks/3ccc3b22.json ] || exit 1
[ ! -f tasks/9e9ff3c4.json ] || exit 1
