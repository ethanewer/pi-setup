#!/bin/bash
# Hidden case (quoin-swell): nested dash-named directories.
# `fd --type f . -` must descend into the real "-" directory in the cwd and
# into dash-named directories nested inside it. Inputs the upstream
# regression test does not use: two levels of "-" nesting, and --type f.
set -u
FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
work=$(mktemp -d /tmp/qsw-nested.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/-/sub/-" || exit 1
echo x > "$work/-/top.txt" || exit 1
echo x > "$work/-/sub/-/deep.txt" || exit 1
( cd "$work" && "$FD_BIN" --type f . - ) > "$work/raw" 2>&1
rc=$?
[ "$rc" -eq 0 ] || exit 1
sort "$work/raw" > "$work/out"
printf '%s\n' "./-/sub/-/deep.txt" "./-/top.txt" | sort > "$work/want"
cmp -s "$work/want" "$work/out" || exit 1
exit 0