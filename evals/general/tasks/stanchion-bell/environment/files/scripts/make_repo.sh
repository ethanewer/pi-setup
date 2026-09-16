#!/usr/bin/env bash
# Builds the shipped git history for the Lanternwell Clinic site at
# image-build time. The working tree is already in place (COPY files/ /app/);
# this script only turns it into a repository with a plausible two-commit
# history. It is gitignored inside /app so the agent's own `git status`
# starts clean.
set -euo pipefail
cd /app || exit 1

rm -rf .git
git init -q -b main

# Scaffolding, content data and the local check tooling.
git add .gitignore README.md package.json vitest.config.mjs vitest.setup.mjs \
  public tools visible
git commit -q -m "chore: scaffolding, page data and local check tooling"

# The site components.
git add src
git commit -q -m "feat: clinic site components and root component"

echo "repository ready: $(git rev-list --count HEAD) commits"