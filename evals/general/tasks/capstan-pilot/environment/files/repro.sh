#!/bin/bash
# Convenience reproducer for capstan-pilot: build a scratch repository and run
# the exact failing command with the tree's freshly built git, using an editor
# that always fails (as a non-interactive caller would). Prints the command's
# exit code and the resulting notes state.
#
# Usage: bash /app/repro.sh
set -u
GITBIN=/app/src/git
WORK=${1:-/tmp/capstan-repro}
rm -rf "$WORK" && mkdir -p "$WORK"
export GIT_EXEC_PATH=/app/src

cd "$WORK" || exit 1
"$GITBIN" init -q .
"$GITBIN" config user.email repro@localhost
"$GITBIN" config user.name repro
echo 'tracked content' > file.txt
"$GITBIN" add file.txt
"$GITBIN" commit -qm initial
empty=$("$GITBIN" hash-object -w /dev/null)
echo "empty blob: $empty"

echo "== running: GIT_EDITOR=false $GITBIN notes add -C <empty-blob> --allow-empty =="
GIT_EDITOR=false "$GITBIN" notes add -C "$empty" --allow-empty 2>&1
rc=$?
echo "== exit code: $rc =="
echo "== notes list after the attempt: =="
listed=$("$GITBIN" notes list 2>&1 || true)
printf '%s\n' "$listed"
echo "== expected behaviour: exit 0, one line '<empty-blob> <commit-sha>' in notes list =="
case "$listed" in
  "$empty"*) exit 0 ;;
  *)
    echo "REPRO FAILED: the empty note was not stored (editor was launched, or contents not recorded)"
    exit 1 ;;
esac