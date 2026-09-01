#!/bin/bash
# Oracle solution for item-030-main.
# 1) inspect history and find leaked credentials
# 2) PRESERVE a recovery copy BEFORE eradicating anything
# 3) rewrite all refs (incl. tags) replacing secrets with <REDACTED>
# 4) update working tree, drop filter-branch backups, expire reflogs,
#    remove ORIG_HEAD, gc-prune, then verify absence everywhere.
set -euo pipefail

cd /app/repo

AWS_ID="AKIAEXAMPLEKEY000001"
AWS_SECRET="EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GH_PAT="ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"

# -- 1. inventory ----------------------------------------------------------
git log --all --oneline || true
echo "--- scanning history for credentials ---"
git log -p --all | grep -E 'AKIA|ghp_' || true

# -- 2. preserve a recovery copy (BEFORE destruction) ----------------------
mkdir -p /app/recovery
cat > /app/recovery/original-secrets.txt <<EOF
$AWS_ID
$AWS_SECRET
$GH_PAT
EOF
echo "recovery copy saved to /app/recovery/original-secrets.txt"

# -- 3. eradicate: rewrite history across ALL refs and tags ----------------
git filter-branch -f --tree-filter '
  python3 - <<"PYEOF"
import glob, os
TOKENS = [
    b"AKIAEXAMPLEKEY000001",
    b"EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0",
    b"ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE",
]
for f in glob.glob("**/*", recursive=True):
    if not os.path.isfile(f):
        continue
    with open(f, "rb") as fh:
        data = fh.read()
    new = data
    for t in TOKENS:
        new = new.replace(t, b"<REDACTED>")
    if new != data:
        with open(f, "wb") as fh:
            fh.write(new)
PYEOF
' --tag-name-filter cat -- --all

# -- 4. working tree -> rewritten HEAD -------------------------------------
git reset -q --hard

# -- 5. drop filter-branch backup refs (they pin the old leaky objects) ----
git for-each-ref --format='%(refname)' refs/original | xargs -r -n1 git update-ref -d

# -- 6. purge reflogs and ORIG_HEAD ----------------------------------------
git reflog expire --expire=now --all
git update-ref -d ORIG_HEAD 2>/dev/null || rm -f .git/ORIG_HEAD

# -- 7. gc prune now --------------------------------------------------------
git gc --prune=now -q

# -- 8. verify ---------------------------------------------------------------
echo "--- verify: remaining token hits in all objects ---"
git fsck --full --no-reflogs 2>/dev/null | awk '{print $3}' | while read -r id; do
  git cat-file -p "$id" 2>/dev/null | grep -aF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" && echo "LEAK FOUND in $id"
done || true

echo "--- verify: worktree scan ---"
grep -rqaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" . --exclude-dir=.git 2>/dev/null && echo "LEAK in worktree" || echo "worktree clean"

echo "DONE"
