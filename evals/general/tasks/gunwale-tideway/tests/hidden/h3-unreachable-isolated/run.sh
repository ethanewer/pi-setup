#!/bin/bash
# Hidden case h3: one remote is unreachable (bad path) alongside a reachable
# one, all fetched with --jobs=0. The upstream regression test only uses
# remotes that always succeed; this proves the default-parallelism path
# still runs the parallel machinery for every remote and that the reachable
# remote's refs arrive even though the command overall reports the failed
# remote. Fails on the unfixed tree (abort before any remote is contacted);
# after the fix the command must exit non-zero, mention the bad remote in
# its output, and still have fetched the good remote's branch.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/hc3.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git init -q --bare "$work/two" || exit 1
wt=$(mktemp -d /tmp/hc3-wt.XXXXXX) || exit 1
git init -q "$wt" || exit 1
( cd "$wt" \
  && git config user.email t@t && git config user.name t \
  && echo hi > f && git add f && git commit -q -m m \
  && git push -q "$work/two" HEAD:master ) || exit 1
rm -rf "$wt"
git init -q "$work/test" || exit 1
( cd "$work/test" \
  && git remote add gone "$work/does-not-exist" \
  && git remote add two "$work/two" ) || exit 1
( cd "$work/test" && "$GIT_BIN" fetch --multiple --jobs=0 gone two ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -ne 0 ] || { echo "expected a non-zero exit for the bad remote" >&2; exit 1; }
grep -qi "does-not-exist" "$work/out" \
    || { echo "output does not mention the bad remote" >&2; exit 1; }
git -C "$work/test" rev-parse --verify --quiet refs/remotes/two/master >/dev/null \
    || { echo "reachable remote was not fetched" >&2; exit 1; }
exit 0