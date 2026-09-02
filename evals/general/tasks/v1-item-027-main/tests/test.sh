#!/bin/bash
# Verifier for item-027-main. Objective checks only.
cd /app/repo 2>/dev/null || { echo 0 > /logs/verifier/reward.txt; exit 0; }

tok_ok=0
conf_ok=0
reach_ok=0
clean_ok=0

# 1) payload/token.dat on disk == "TOKEN-X7Y9"
if [ -f payload/token.dat ]; then
  t=$(cat payload/token.dat | sed 's/\r$//' | tr -d '\r' | tr -d '\n')
  if [ "$t" = "TOKEN-X7Y9" ]; then tok_ok=1; fi
fi

# 2) payload.conf has both required lines
if [ -f payload.conf ]; then
  if grep -q '^priority=prod' payload.conf && grep -q '^server=mid' payload.conf; then
    conf_ok=1
  fi
fi

# 3) token.dat reaches: committed in HEAD tree
if git rev-parse HEAD >/dev/null 2>&1; then
  if git ls-tree HEAD payload/token.dat >/dev/null 2>&1; then
    reach_ok=1
  fi
fi

# 4) not mid-conflict and repo object store healthy
clean_ok=1
for marker in ".git/MERGE_HEAD" ".git/REBASE_HEAD" ".git/CHERRY_PICK_HEAD"; do
  if [ -f "$marker" ]; then clean_ok=0; fi
done
if command -v git >/dev/null; then
  fs=$(git fsck --full 2>/dev/null)
  if grep -qE '^missing|^broken' <<<"$fs"; then clean_ok=0; fi
else
  clean_ok=0
fi

# require recovery BEFORE cleanup: run gc, confirm token still reachable afterward
if [ "$tok_ok" = "1" ] && [ "$reach_ok" = "1" ]; then
  git gc -q 2>/dev/null
  if ! git ls-tree HEAD payload/token.dat >/dev/null 2>&1; then reach_ok=0; fi
fi

reward=0
if [ "$tok_ok" = "1" ] && [ "$conf_ok" = "1" ] && [ "$reach_ok" = "1" ] && [ "$clean_ok" = "1" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt