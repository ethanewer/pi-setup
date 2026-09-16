#!/bin/bash
# Hidden case 1: multiple untracked files AT THE REPO ROOT matched by a single
# glob-magic pathspec ':(glob)**/*.md', plus a sibling .txt that must survive.
# (The upstream golden test only ever stashes ONE root-level untracked .txt.)
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-glob.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
mkdir -p app/src
printf 'int main(void){return 0;}\n' > app/src/app.c
"$GITBIN" add app/src/app.c
"$GITBIN" commit -qm init

printf 'release notes\n' > RELEASE.md
printf 'scratch pad\n'   > scratch.md
printf 'do not touch\n'  > README.txt

out=$("$GITBIN" stash push -u -m h1 -- ':(glob)**/*.md' 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc1: stash exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
# matched .md files must be gone; unmatched and tracked files must remain
for f in RELEASE.md scratch.md; do
  if [ -e "$f" ]; then echo "FAIL hc1: $f still present"; exit 1; fi
done
if [ ! -e README.txt ]; then echo "FAIL hc1: README.txt wrongly removed"; exit 1; fi
if [ ! -e app/src/app.c ]; then echo "FAIL hc1: tracked app/src/app.c removed"; exit 1; fi
# the stash must actually hold the files and restore them on pop
"$GITBIN" stash pop -q || { echo "FAIL hc1: stash pop failed"; exit 1; }
if [ "$(cat RELEASE.md)" != "release notes" ]; then echo "FAIL hc1: RELEASE.md content"; exit 1; fi
if [ "$(cat scratch.md)" != "scratch pad" ]; then echo "FAIL hc1: scratch.md content"; exit 1; fi
echo "PASS hc1"
exit 0
