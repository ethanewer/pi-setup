#!/bin/bash
# Hidden case h1: THREE remotes with distinct branch names, fetched with
# --jobs=0 PLUS --tags. The upstream regression test uses two remotes,
# default refspecs and no --tags; this exercises the same parallel
# multi-remote path from inputs it does not use. Fails on the unfixed tree
# (BUG diagnostic, abort, nothing fetched); must exit 0 with every
# remote-tracking ref AND every tag present after the fix.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/hc1.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
seed() { # $1=bare repo path  $2=branch  $3=tag name (or empty)
    git init -q --bare "$1" || exit 1
    wt=$(mktemp -d /tmp/hc1-wt.XXXXXX) || exit 1
    git init -q "$wt" || exit 1
    ( cd "$wt" \
      && git config user.email t@t && git config user.name t \
      && echo seed > f && git add f && git commit -q -m seed \
      && git push -q "$1" HEAD:refs/heads/"$2" ) || exit 1
    if [ -n "${3:-}" ]; then
        ( cd "$wt" && git tag "$3" && git push -q "$1" refs/tags/"$3" ) \
            || exit 1
    fi
    rm -rf "$wt"
}
seed "$work/one"   master t-one
seed "$work/two"   main   t-two
seed "$work/three" dev
git init -q "$work/test" || exit 1
( cd "$work/test" \
  && git remote add one "$work/one" \
  && git remote add two "$work/two" \
  && git remote add three "$work/three" ) || exit 1
( cd "$work/test" && "$GIT_BIN" fetch --multiple --jobs=0 --tags one two three ) \
    > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
( cd "$work/test" \
  && git rev-parse --verify --quiet refs/remotes/one/master >/dev/null \
  && git rev-parse --verify --quiet refs/remotes/two/main >/dev/null \
  && git rev-parse --verify --quiet refs/remotes/three/dev >/dev/null \
  && git rev-parse --verify --quiet refs/tags/t-one >/dev/null \
  && git rev-parse --verify --quiet refs/tags/t-two >/dev/null ) \
    || { echo "missing refs/tags after fetch" >&2; exit 1; }
exit 0