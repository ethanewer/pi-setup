#!/bin/bash
# Hidden case 2: run `git stash -u -- ':(glob)**/*.tmp'` FROM A SUBDIRECTORY
# whose own contents are the untracked targets (a file directly in the cwd and
# one nested deeper). This never appears in the upstream golden test, which
# always stashes from the repo root.
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-sub.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
mkdir -p proj/src/proto
printf 'int g=1;\n' > proj/src/proto/lib.c
"$GITBIN" add proj/src/proto/lib.c
"$GITBIN" commit -qm init

printf 'temp A\n'      > proj/src/tmp_A.tmp
mkdir -p proj/src/deep
printf 'temp B\n'      > proj/src/deep/tmp_B.tmp
printf 'keep me\n'     > proj/src/keep.c
printf 'outside\n'     > proj/outside.tmp

out=$(cd proj/src && "$GITBIN" stash -u -- ':(glob)**/*.tmp' 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc2: stash exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
for f in proj/src/tmp_A.tmp proj/src/deep/tmp_B.tmp; do
  if [ -e "$f" ]; then echo "FAIL hc2: $f still present"; exit 1; fi
done
if [ ! -e proj/src/keep.c ]; then echo "FAIL hc2: keep.c wrongly removed"; exit 1; fi
if [ ! -e proj/outside.tmp ]; then echo "FAIL hc2: outside.tmp (not under cwd) wrongly removed"; exit 1; fi
if [ ! -e proj/src/proto/lib.c ]; then echo "FAIL hc2: tracked lib.c removed"; exit 1; fi
"$GITBIN" stash pop -q || { echo "FAIL hc2: stash pop failed"; exit 1; }
if [ "$(cat proj/src/tmp_A.tmp)" != "temp A" ]; then echo "FAIL hc2: tmp_A.tmp content"; exit 1; fi
if [ "$(cat proj/src/deep/tmp_B.tmp)" != "temp B" ]; then echo "FAIL hc2: tmp_B.tmp content"; exit 1; fi
echo "PASS hc2"
exit 0
