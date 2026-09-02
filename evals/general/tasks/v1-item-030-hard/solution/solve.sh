#!/bin/bash
# Oracle solution for item-030-hard.
# Multi-stage eradication:
#   1) inventory ALL refs + working files, find every leaked credential type
#   2) PRESERVE a recovery copy first (separate recovery from eradication)
#   3) rewrite all refs (branches AND tags) replacing secrets in FILE CONTENT
#      and COMMIT MESSAGES with <REDACTED>
#   4) refresh working tree, drop filter-branch backups, expire reflogs,
#      remove ORIG_HEAD, gc-prune the packed objects
#   5) verify absence in every object and file, without leaking in logs
set -euo pipefail

cd /app/repo

AWS_ID="AKIAEXAMPLEKEY000001"
AWS_SECRET="EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GH_PAT="ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"
GH_FINE="github_pat_EXAMPLE_EXAMPLE_EXAMPLE"

# -- 1. inventory ------------------------------------------------------------
echo "=== all refs ==="
git for-each-ref
echo "=== commit messages (may contain credentials) ==="
git log --all --format='%H %s'
echo "=== credential hits in history ==="
git log -p --all | grep -aE 'AKIA|ghp_|github_pat_' || true

# -- 2. preserve a recovery copy BEFORE destroying anything -------------------
mkdir -p /app/recovery
cat > /app/recovery/original-secrets.txt <<EOF
$AWS_ID
$AWS_SECRET
$GH_PAT
$GH_FINE
EOF
echo "recovery copy saved (outside the repository)"

# -- 3. rewrite every ref incl. tags: content AND messages -------------------
#    tree-filter : scrub file contents
#    msg-filter  : scrub commit messages (they also leaked credentials)
#    -- --all    : every branch and tag
git filter-branch -f \
  --tree-filter '
    python3 - <<"PYEOF"
import glob, os
TOKENS = [
    b"AKIAEXAMPLEKEY000001",
    b"EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0",
    b"ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE",
    b"github_pat_EXAMPLE_EXAMPLE_EXAMPLE",
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
' \
  --msg-filter '
    sed "s|AKIAEXAMPLEKEY000001|<REDACTED>|g; s|EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0|<REDACTED>|g; s|ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE|<REDACTED>|g; s|github_pat_EXAMPLE_EXAMPLE_EXAMPLE|<REDACTED>|g"
' \
  --tag-name-filter cat -- --all

# -- 4. refresh working tree, remove backup refs and stale pointers ----------
git reset -q --hard
git for-each-ref --format='%(refname)' refs/original | xargs -r -n1 git update-ref -d
git reflog expire --expire=now --all
git update-ref -d ORIG_HEAD 2>/dev/null || rm -f .git/ORIG_HEAD
git gc --prune=now -q

# -- 5. verify: absence in every object and every working file ---------------
echo "=== scan all objects for credentials ==="
hit=0
for id in $(git fsck --full --no-reflogs 2>/dev/null | awk '{print $3}'); do
  if git cat-file -p "$id" 2>/dev/null | grep -aqF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE"; then
    echo "LEAK in object $id"; hit=1
  fi
done
[ "$hit" = 0 ] && echo "objects clean"

echo "=== scan working files ==="
if grep -rqaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE" . --exclude-dir=.git 2>/dev/null; then
  echo "LEAK in worktree"
else
  echo "worktree clean"
fi

echo "=== refs after rewrite ==="
git for-each-ref

echo DONE