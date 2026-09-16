#!/bin/bash
# Hidden case (quoin-swell): the dash path supplied through the long option
# form (`--search-path -`) instead of the positional form. Both routes feed
# the same search-path normalisation; the upstream regression test only
# exercises the positional form.
set -u
FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
work=$(mktemp -d /tmp/qsw-longopt.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/-" || exit 1
echo x > "$work/-/sp.txt" || exit 1
( cd "$work" && "$FD_BIN" . --search-path - ) > "$work/raw" 2>&1
rc=$?
[ "$rc" -eq 0 ] || exit 1
sort "$work/raw" > "$work/out"
printf '%s\n' "./-/sp.txt" | sort > "$work/want"
cmp -s "$work/want" "$work/out" || exit 1
exit 0