#!/bin/bash
# Hidden case h1: EMPTY pattern on a two-line "\W\W" input ("\n##\n##\n").
# The upstream regression test uses a single "##" line; this exercises the
# same word-matching empty-pattern fast path from a different input layout.
# Fails on the unfixed tree (panic, exit 101); must pass on the fixed tree
# with the exact expected output in expected.txt.
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
HERE=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/hc1.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf '\n##\n##\n' > "$work/u.txt"
( cd "$work" && "$RG_BIN" -won '' u.txt ) > "$work/out" 2> "$work/err"
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
cmp -s "$work/out" "$HERE/expected.txt" || { echo "output mismatch" >&2; exit 1; }
exit 0