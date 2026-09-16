#!/usr/bin/env bash
# Build the Halyard yard git repository at /app/yard from a flat file tree,
# committing it in logical increments so the fixture ships real history.
#
# This runs once at image-build time (networking is available then). It is
# reproducible: re-running it on the same file tree produces the same commits.
set -euo pipefail

REPO=/app/yard

cd "$REPO"

# Repo is created fresh; discard any prior history if re-run for debugging.
if [ -d .git ]; then rm -rf .git; fi
git init -q -b main
git config user.email "build@halyard.local"
git config user.name "halyard-build"

commit_all() {
  git add -A
  git commit -q -m "$1"
}

# 1. project scaffolding
git add README.md pyproject.toml
git commit -q -m "chore: scaffold halyard-yard project and packaging metadata"

# 2. metric catalogue and alerting contract (the source of truth)
git add src/yard/metrics.py src/yard/alerting.py
git commit -q -m "feat: metric catalogue and alerting contract for the four sub-systems"

# 3. the yard simulation itself
git add src/yard/components.py src/yard/simulator.py src/yard/__init__.py
git commit -q -m "feat: lockstep yard simulator and per-area samplers"

# 4. operational documentation
git add docs/runbook.md
git commit -q -m "docs: author the Halyard operations runbook"

# 5. monitoring wiring + the visible alerting unit-test scenario
git add monitoring/
git commit -q -m "feat: prometheus scaffold and visible alerting test scenario"

# 6. the application test suite
git add tests/
git commit -q -m "test: pin metric catalogue, sampler behaviour and alerting contract"

echo "built $(git rev-list --count HEAD) commits in $REPO"
