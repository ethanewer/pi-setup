#!/usr/bin/env bash
# Builds the fluxline git history at image-build time (the harness never
# persists .git directories through COPY, so the repository is created here
# with incremental commits). Leaves the working tree at the shipped HEAD.
#
# The history tells two facts about the project: the scaffold that added
# the config loader and workload generator, and the feature commit that
# added the streaming pipeline with its concurrent async transform, its
# tests, and the documented working-set budget.
set -euo pipefail
cd /app/fluxline

git init -q -b main
git config user.name "build"
git config user.email "build@localhost"
git config commit.gpgsign false

# --- commit 1: scaffold ---
git add package.json .gitignore lib/config.js scripts/gen_fixture.mjs data/
git commit -q -m "scaffold: fluxline project, config loader, workload generator, sample data"

# --- commit 2: the pipeline itself ---
git add lib/pipeline.js lib/transform.js test/ README.md
git commit -q -m "feat: streaming ndjson pipeline with concurrent row enrichment (#118)"

git log --oneline | head -3