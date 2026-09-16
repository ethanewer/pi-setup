#!/bin/bash
# Hidden case h2: an established remote configuration fetched again after
# the remotes advanced - one remote's branch tip moves to a new commit, a
# second remote gains a new branch. The upstream regression test only
# fetches fresh remotes once; this proves the --jobs=0 default-parallelism
# path transfers the actual new objects/refs on repeated fetches, not just
# that the command exits 0. Fails on the unfixed tree (abort on the very
# first fetch); must exit 0 with all refs at their new tips after the fix.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/hc2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
seed() { # $1=bare repo path  $2=branch
    git init -q --bare "$1" || exit 1
    wt=$(mktemp -d /tmp/hc2-wt.XXXXXX) || exit 1
    git init -q "$wt" || exit 1
    ( cd "$wt" \
      && git config user.email t@t && git config user.name t \
      && echo v1 > f && git add f && git commit -q -m v1 \
      && git push -q "$1" HEAD:refs/heads/"$2" ) || exit 1
    rm -rf "$wt"
}
seed "$work/one" master
seed "$work/two" main
git init -q "$work/test" || exit 1
( cd "$work/test" \
  && git remote add one "$work/one" \
  && git remote add two "$work/two" ) || exit 1
( cd "$work/test" && "$GIT_BIN" fetch --multiple --jobs=0 one two ) > /dev/null 2>&1 \
    || { echo "first fetch failed" >&2; exit 1; }

# advance one, add a branch to two, then fetch again with --jobs=0
wt=$(mktemp -d /tmp/hc2-wt.XXXXXX) || exit 1
git init -q "$wt" || exit 1
( cd "$wt" \
  && git config user.email t@t && git config user.name t \
  && git clone -q --no-hardlinks "$work/one" c >/dev/null 2>&1 \
  && cd c && git config user.email t@t && git config user.name t \
  && echo v2 > g && git add g && git commit -q -m v2 \
  && git push -q origin master ) || { rm -rf "$wt"; echo "seed advance failed" >&2; exit 1; }
( cd "$wt" \
  && git init -q n && cd n && git config user.email t@t && git config user.name t \
  && echo topic > t2 && git add t2 && git commit -q -m topic \
  && git remote add origin "$work/two" && git push -q origin HEAD:refs/heads/topic ) \
    || { rm -rf "$wt"; echo "seed topic failed" >&2; exit 1; }
rm -rf "$wt"

one_tip=$(git -C "$work/one" rev-parse master) || exit 1
( cd "$work/test" && "$GIT_BIN" fetch --multiple --jobs=0 one two ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
( cd "$work/test" \
  && test "$(git rev-parse --verify refs/remotes/one/master)" = "$one_tip" \
  && git rev-parse --verify --quiet refs/remotes/two/topic >/dev/null \
  && git rev-parse --verify --quiet refs/remotes/two/main >/dev/null ) \
    || { echo "refs not at expected tips after fetch" >&2; exit 1; }
exit 0