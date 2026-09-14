#!/bin/bash
# Hidden case (quoin-swell): filtered pattern against the dash directory.
# `fd '\.log$' -` must search the real "-" directory and apply the pattern
# inside it, returning only the matching file. The upstream regression test
# uses pattern "." only; this uses a real filter and a non-matching sibling.
set -u
FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
work=$(mktemp -d /tmp/qsw-pattern.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/-" || exit 1
echo x > "$work/-/alpha.log" || exit 1
echo x > "$work/-/beta.txt" || exit 1
( cd "$work" && "$FD_BIN" '\.log$' - ) > "$work/raw" 2>&1
rc=$?
[ "$rc" -eq 0 ] || exit 1
sort "$work/raw" > "$work/out"
printf '%s\n' "./-/alpha.log" | sort > "$work/want"
cmp -s "$work/want" "$work/out" || exit 1
exit 0