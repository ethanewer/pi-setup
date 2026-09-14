#!/bin/bash
# Hidden case h3: pattern `^` (an anchor that matches the empty string) on
# "\n##\n". The upstream regression test uses the empty pattern; this reaches
# the same word-matching empty-match fast path from a different
# empty-matchable pattern. Fails on the unfixed tree (panic, exit 101); must
# pass on the fixed tree with the exact expected output in expected.txt.
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
HERE=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/hc3.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf '\n##\n' > "$work/u.txt"
( cd "$work" && "$RG_BIN" -won '^' u.txt ) > "$work/out" 2> "$work/err"
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
cmp -s "$work/out" "$HERE/expected.txt" || { echo "output mismatch" >&2; exit 1; }
exit 0