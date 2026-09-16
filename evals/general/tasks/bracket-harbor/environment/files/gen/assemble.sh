#!/bin/bash
# Assembles the bh repository stage by stage, committing each stage so the
# shipped .git history is real and greppable. Stage order matters: the
# precedence refactor sits exactly two commits before HEAD, and every earlier
# commit must leave the suite green.
set -euo pipefail
cd /app

OUT=/app/bh
rm -rf "$OUT"
mkdir -p "$OUT"

export GIT_AUTHOR_NAME=build
export GIT_AUTHOR_EMAIL=build@localhost
export GIT_COMMITTER_NAME=build
export GIT_COMMITTER_EMAIL=build@localhost

git init -q -b main "$OUT"

stage() {
  local name=$1
  local msg=$2
  python3 /app/gen/generate_repo.py --stage "$name" --out "$OUT"
  ( cd "$OUT" && git add -A
    if git diff --cached --quiet; then
      echo "stage $name: no changes, skipping"
    else
      git commit -q -m "$msg"
      echo "stage $name: committed"
    fi )
}

stage base      "bootstrap: module skeleton and project docs"
stage version   "feat(version): build identity and feature flags"
stage token     "feat(token): token kinds, keyword table, canonical keys, operator tiers"
stage lexer     "feat(lexer): tokenizer for the query language"
stage ast       "feat(ast): condition tree model and canonical formatter"
stage parser    "feat(parser): precedence-climbing condition and query parser"
stage store     "feat(store): fixed-schema in-memory row store"
stage idx       "feat(idx): canonical-key inverted indexes"
stage schema    "feat(schema): field type registry and coercion"
stage query     "feat(query): condition normalization, evaluation and selection"
stage report    "feat(report): aligned table and csv rendering with totals"
stage conf      "feat(conf): sectioned key=value configuration loader"
stage cmd       "feat(cmd): bh command-line frontend and smoke tests"
stage planner   "feat(idx): planner hints and key statistics"
stage refactor  "refactor(token): fold boolean operator precedence tiers"
stage reportal  "feat(report): alignment cap option and right-justified totals"
stage head      "chore(cmd): banner and flag parsing polish"

cd "$OUT"
git log --oneline | head -20
echo "assemble done: $(git rev-list --count HEAD) commits at $(pwd)"