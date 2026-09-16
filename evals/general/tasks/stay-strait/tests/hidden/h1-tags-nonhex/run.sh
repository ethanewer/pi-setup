#!/bin/bash
# Hidden case h1: corrupt ref file under refs/tags/ whose contents are 40
# characters of non-hex garbage. The upstream regression test only corrupts
# a refs/heads/ file with a single non-hex character; this exercises the
# same local-clone ref-scanning path from a different namespace and
# different invalid content. Must fail cleanly (rc 128, no BUG: line, a
# 'null OID' fatal diagnostic) on the fixed tree; on the pre-fix binary it
# must crash (abort, rc 134) instead.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/hc1.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
( mkdir -p "$work/src" && cd "$work/src" \
  && "$GIT_BIN" init -q \
  && "$GIT_BIN" config user.email t@t \
  && "$GIT_BIN" config user.name t \
  && echo one > one \
  && "$GIT_BIN" add one \
  && "$GIT_BIN" commit -q -m one ) || exit 1
mkdir -p "$work/src/.git/refs/tags" || exit 1
printf 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' > "$work/src/.git/refs/tags/v1.0" || exit 1
( cd "$work" && "$GIT_BIN" clone src dst ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 128 ] || { echo "expected clean failure rc=128, got $rc" >&2; exit 1; }
grep -q "has a null OID" "$work/out" || { echo "no 'has a null OID' diagnostic" >&2; exit 1; }
grep -q "^BUG:" "$work/out" && { echo "BUG: line present" >&2; exit 1; }
exit 0