#!/bin/bash
# Build the coursebook repository's git history at image-build time.
#
# The repo sources are shipped under environment/files/coursebook/ and copied
# to /app/coursebook by the Dockerfile.  This script wipes any stray .git,
# then commits the tree in logical, realistic increments so the agent inherits
# a repository with a real history rather than a single snapshot.
#
# Committer identity and safe.directory are set system-wide in the Dockerfile,
# so this runs as root and the trial can run the repo as any user.
set -euo pipefail

cd /app/coursebook

rm -rf .git
git -c init.defaultBranch=main init -q

git add pyproject.toml coursebook/__init__.py .gitignore
git commit -qm "scaffold coursebook project"

git add coursebook/errors.py coursebook/db.py coursebook/store.py
git commit -qm "add storage layer: schema, domain operations, error types"

git add coursebook/cli.py coursebook/__main__.py
git commit -qm "add command-line interface over the store"

git add tests/
git commit -qm "pin registration behaviour with the test suite"

git add README.md
git commit -qm "document the registration invariant"

echo "built history:"
git log --oneline