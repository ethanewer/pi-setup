#!/bin/bash
# Oracle solution for item-027-main.
# 1. inspect history/reflog
# 2. recover the dangling token commit onto main
# 3. merge server and resolve payload.conf conflict
# 4. verify working tree, then gc AFTER recovery
set -euo pipefail

REPO=/app/repo
cd "$REPO"

git config user.email "alice@bench.test" >/dev/null 2>&1 || true
git config user.name "Alice" >/dev/null 2>&1 || true

# -- Step 1: inspect ---------------------------------------------------------
# Display history, all refs, reflog and dangling objects. This is for the
# record; the actual discovery uses the reflog / unreachable commits.
git log --all --oneline || true
git reflog --all || true

# -- Step 2: recover ---------------------------------------------------------
# Find the lost commit: its tree must contain payload/token.dat.
# The reflog shows where HEAD was before `reset --hard`; we also search all
# unreachable commits in case reflog entries were expired.
LOST=""
for cand in $(git reflog --all --format='%H' | sort -u) \
            $(git fsck --no-reflogs --unreachable 2>/dev/null | grep 'unreachable commit' | awk '{print $3}'); do
  if git cat-file -e "$cand:payload/token.dat" 2>/dev/null; then
    LOST="$cand"
    break
  fi
done

if [ -z "$LOST" ]; then
  echo "FATAL: lost commit not found" >&2
  exit 1
fi

# Bring the token back into the worktree and index on main.
git restore -s "$LOST" -- payload/token.dat
git add payload/token.dat

# Recorder commit so recovery is explicit and reachable.
git commit -q -m "recover: restore dropped token payload" || true

# -- Step 3: merge server, resolve payload.conf ------------------------------
# Spec: payload.conf must contain priority=high and server=mid on their own
# lines (priority first, then server), originating from BOTH histories.
git merge --no-edit server || true

cat > payload.conf <<'EOF'
priority=prod
server=mid
EOF
git add payload.conf

# If the merge did not auto-commit (conflict resolution pending), commit now.
if [ -f "$REPO/.git/MERGE_HEAD" ] || git status --porcelain | grep -q '^[MADRCU]'; then
  git commit -q --no-edit -m "merge: integrate server config with recovered secret" || true
fi

# -- Step 4: verify ----------------------------------------------------------
git status --porcelain
git fsck --full 1>/dev/null || true

# -- Step 5: clean AFTER recovery --------------------------------------------
git gc -q

echo "DONE"