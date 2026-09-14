#!/bin/bash
# Hidden case h2: pattern `t?` (empty-matchable but NOT the empty pattern) on
# a mixed input "test\n##\n". The upstream regression test uses the empty
# pattern on an all-hash input; this reaches the same word-matching fast path
# from a different pattern, with real content on the first line. Fails on the
# unfixed tree (panic, exit 101); must pass on the fixed tree with the exact
# expected output in expected.txt.
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
HERE=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/hc2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'test\n##\n' > "$work/u.txt"
( cd "$work" && "$RG_BIN" -won 't?' u.txt ) > "$work/out" 2> "$work/err"
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
cmp -s "$work/out" "$HERE/expected.txt" || { echo "output mismatch" >&2; exit 1; }
exit 0