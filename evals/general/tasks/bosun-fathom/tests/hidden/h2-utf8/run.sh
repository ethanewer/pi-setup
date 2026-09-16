#!/bin/bash
# Hidden case h2: UTF-8 multibyte (non-ASCII) lines, searched recursively
# with a max-count limit. "bytes searched" must count BYTES, not characters:
# each line "h\u00e9lloN\n" is 8 bytes (the accented e is two bytes). The
# upstream regression test uses plain-ASCII input; this exercises the same
# early-stop byte-accounting path (the recursive directory-search form) on
# multibyte data. Fails on the unfixed tree ("0 bytes searched"); must exit 0
# with "3 matches" and "24 bytes searched" after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'h\xc3\xa9llo1\nh\xc3\xa9llo2\nh\xc3\xa9llo3\nh\xc3\xa9llo4\n' > "$work/f.txt" || exit 1
# Sanity: each line must be exactly 8 bytes (incl. newline) for the
# expectation below; 'bytes searched' must count bytes, not characters.
fl=$(head -1 "$work/f.txt" | wc -c) || exit 1
[ "$fl" = "8" ] || { echo "fixture line is $fl bytes, expected 8" >&2; exit 1; }
( cd "$work" && "$RG_BIN" --stats -m3 llo . ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
matches_line=$(grep -o '[0-9][0-9]* matches' "$work/out" | head -1)
[ "$matches_line" = "3 matches" ] || { echo "expected '3 matches'" >&2; exit 1; }
bytes_line=$(grep -o '[0-9][0-9]* bytes searched' "$work/out" | head -1)
# 3 consumed lines x 8 bytes = 24.
[ "$bytes_line" = "24 bytes searched" ] || { echo "expected '24 bytes searched'" >&2; exit 1; }
exit 0