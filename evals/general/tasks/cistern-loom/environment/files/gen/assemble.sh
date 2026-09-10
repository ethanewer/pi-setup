#!/usr/bin/env bash
# Assembles the cistern repository at /app/cistern stage by stage, so the
# shipped .git history is real: each commit leaves the tree in a coherent
# state, and the final commits tell the exact story the task relies on
# (legacy importers rewritten without type annotations, strict mode then
# disabled in tsconfig).
set -euo pipefail

OUT=/app/cistern
export GIT_AUTHOR_NAME=build
export GIT_AUTHOR_EMAIL=build@cistern.local
export GIT_COMMITTER_NAME=build
export GIT_COMMITTER_EMAIL=build@cistern.local

rm -rf "$OUT"
mkdir -p "$OUT"
git init -q -b main "$OUT"

stage() {
  local name=$1
  shift
  python3 /app/gen/assemble.py --out "$OUT" --mode loose --stage "$name" >/dev/null
  ( cd "$OUT" && git add -A
    if git diff --cached --quiet; then
      echo "stage $name: no changes, skipping"
    else
      git commit -q -m "$1"
      echo "stage $name: committed"
    fi )
}

stage bootstrap  "bootstrap: package metadata, tooling config and util layer"
stage model      "feat(model): config freezing, network graph, zones and store"
stage data       "feat(data): records, telemetry, ledgers, tariffs and presets"
stage algo       "feat(algo): flow balance, leak detection, clustering and forecast"
stage reports    "feat(reports): table rendering, zone and billing reports"
stage service    "feat(service): ingest pipeline and reconcile orchestration"
stage legacy     "feat(legacy): flat-file importers kept for compatibility"
stage api        "feat(api): full public surface exported from index"
stage tests      "test: vitest suite locking the public behaviour"

# Final state of the working tree head: the legacy importers were rewritten
# without annotations and strict mode was switched off afterwards, which is
# exactly the state the agent finds.
cd "$OUT"
npm install --no-audit --no-fund --no-progress >/dev/null 2>&1

python3 /app/gen/assemble.py --out "$OUT" --mode loose >/dev/null
git add -A
git commit -q -m "refactor(legacy): importers rewritten without type annotations
chore(tsconfig): disable strict mode until the migration lands"

head_commit=$(git rev-parse --short HEAD)
echo "cistern built with $(git rev-list --count HEAD) commits, head=$head_commit"
git log --oneline | head -14