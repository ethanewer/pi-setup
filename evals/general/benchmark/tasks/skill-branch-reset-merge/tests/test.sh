#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
cd /app/workflow || { echo "0" > /logs/verifier/reward.txt; exit 0; }

tree_ok=0
if git cat-file -e main:util.py 2>/dev/null && git cat-file -e main:test_util.py 2>/dev/null \
   && git cat-file -e main:app.py 2>/dev/null \
   && ! git cat-file -e main:experiment.py 2>/dev/null \
   && ! git cat-file -e main:junk.txt 2>/dev/null; then
  tree_ok=1
fi

util_ok=0
if git show main:util.py 2>/dev/null | grep -q 'return n \* 2' \
   && ! git show main:util.py 2>/dev/null | grep -q 'WIP experiment' \
   && ! git show main:util.py 2>/dev/null | grep -q 'JUNK'; then
  util_ok=1
fi

hist_ok=0
if ! git log main --all --diff-filter=A --name-only --format='' 2>/dev/null | grep -qE 'experiment\.py|junk\.txt'; then
  hist_ok=1
fi

merge_ok=0
if [ -n "$(git rev-list --merges main -n 1 2>/dev/null)" ]; then
  merge_ok=1
fi

clean_ok=0
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  clean_ok=1
fi

if [ "$tree_ok" = 1 ] && [ "$util_ok" = 1 ] && [ "$hist_ok" = 1 ] && [ "$merge_ok" = 1 ] && [ "$clean_ok" = 1 ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
