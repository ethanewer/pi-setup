#!/bin/bash
# Hidden case h3: CRLF line endings (\\r\\n), searched recursively with a
# max-count limit. "bytes searched" must count every byte of the consumed
# input, including the carriage returns: each line "fooN\\r\\n" is 6
# bytes. The upstream regression test uses LF-only input; this exercises the
# same early-stop byte-accounting path (the recursive directory-search form)
# on CRLF data. Fails on the unfixed tree ("0 bytes searched"); must exit 0
# with "2 matches" and "12 bytes searched" after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc3.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'foo1\r\nfoo2\r\nfoo3\r\nfoo4\r\nfoo5\r\n' > "$work/g.txt" || exit 1
# Sanity: each line must be exactly 6 bytes (incl. CRLF) for the
# expectation below.
fl=$(head -1 "$work/g.txt" | wc -c) || exit 1
[ "$fl" = "6" ] || { echo "fixture line is $fl bytes, expected 6" >&2; exit 1; }
( cd "$work" && "$RG_BIN" --stats -m2 foo . ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
matches_line=$(grep -o '[0-9][0-9]* matches' "$work/out" | head -1)
[ "$matches_line" = "2 matches" ] || { echo "expected '2 matches'" >&2; exit 1; }
bytes_line=$(grep -o '[0-9][0-9]* bytes searched' "$work/out" | head -1)
# 2 consumed lines x 6 bytes = 12.
[ "$bytes_line" = "12 bytes searched" ] || { echo "expected '12 bytes searched'" >&2; exit 1; }
exit 0