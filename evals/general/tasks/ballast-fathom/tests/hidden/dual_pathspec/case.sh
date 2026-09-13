#!/bin/bash
# Hidden case 3: TWO glob-magic pathspecs of different extensions passed to a
# single `git stash -u` command in one repo. The upstream golden test only
# ever passes one pathspec.
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-dual.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
mkdir -p src
printf 'int h=0;\n' > src/main.c
"$GITBIN" add src/main.c
"$GITBIN" commit -qm init

printf 'alpha beta\n' > alpha.md
printf 'gamma delta\n' > gamma.txt
printf 'epsilon zeta\n' > keep.log

out=$("$GITBIN" stash -u -- ':(glob)**/*.md' ':(glob)**/*.txt' 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc3: stash exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
for f in alpha.md gamma.txt; do
  if [ -e "$f" ]; then echo "FAIL hc3: $f still present"; exit 1; fi
done
if [ ! -e keep.log ]; then echo "FAIL hc3: keep.log wrongly removed"; exit 1; fi
if [ ! -e src/main.c ]; then echo "FAIL hc3: tracked src/main.c removed"; exit 1; fi
"$GITBIN" stash pop -q || { echo "FAIL hc3: stash pop failed"; exit 1; }
if [ "$(cat alpha.md)" != "alpha beta" ]; then echo "FAIL hc3: alpha.md content"; exit 1; fi
if [ "$(cat gamma.txt)" != "gamma delta" ]; then echo "FAIL hc3: gamma.txt content"; exit 1; fi
echo "PASS hc3"
exit 0
