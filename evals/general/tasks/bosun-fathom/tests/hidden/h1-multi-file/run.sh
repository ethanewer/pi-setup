#!/bin/bash
# Hidden case h1: TWO files with DIFFERENT line sizes, searched recursively
# with a per-file max-count limit. The upstream regression test uses a single
# file with uniform 5-byte lines; this exercises the same early-stop
# byte-accounting path (the recursive directory-search form) from inputs it
# does not use. Fails on the unfixed tree ("0 bytes searched"); must exit 0
# with the exact "4 matches" and "22 bytes searched" after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc1.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
# a.txt: four 5-byte lines; b.txt: three 6-byte lines.
printf 'red1\nred2\nred3\nred4\n' > "$work/a.txt" || exit 1
printf 'blue1\nblue2\nblue3\n'    > "$work/b.txt" || exit 1
( cd "$work" && "$RG_BIN" --stats -m2 'red|blue' . ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
matches_line=$(grep -o '[0-9][0-9]* matches' "$work/out" | head -1)
[ "$matches_line" = "4 matches" ] || { echo "expected '4 matches'" >&2; exit 1; }
bytes_line=$(grep -o '[0-9][0-9]* bytes searched' "$work/out" | head -1)
# 2 consumed lines of a.txt (2x5) + 2 consumed lines of b.txt (2x6) = 22.
[ "$bytes_line" = "22 bytes searched" ] || { echo "expected '22 bytes searched'" >&2; exit 1; }
exit 0