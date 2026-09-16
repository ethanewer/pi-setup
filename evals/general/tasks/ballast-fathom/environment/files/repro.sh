#!/bin/bash
# Convenience reproducer for ballast-fathom: build a scratch repository with a
# tracked file, an untracked .txt file, and run the raw repro command against
# the tree's freshly built git. Prints the command's exit code.
#
# Usage: bash /app/repro.sh
set -u
GITBIN=/app/src/git
WORK=${1:-/tmp/ballast-repro}
rm -rf "$WORK" && mkdir -p "$WORK"
export GIT_EXEC_PATH=/app/src

cd "$WORK" || exit 1
"$GITBIN" init -q .
"$GITBIN" config user.email repro@localhost
"$GITBIN" config user.name repro
echo 'tracked content' > tracked.txt
"$GITBIN" add tracked.txt
"$GITBIN" commit -qm initial
echo 'untracked data' > untracked.txt

echo "== running: $GITBIN stash -u -- ':(glob)**/*.txt' =="
"$GITBIN" stash -u -- ':(glob)**/*.txt'
rc=$?
echo "== exit code: $rc =="
echo "== files left in worktree: =="
ls -1
exit 0
