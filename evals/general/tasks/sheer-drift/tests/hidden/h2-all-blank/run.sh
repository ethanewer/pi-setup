#!/bin/bash
# Hidden case h2: an all-blank file (three newline-only lines, input the
# upstream test does not use). At the parent commit this input panics with
# "index out of bounds" (rc 101); the repaired binary must exit 0 and print
# exactly "\r\n\r\n\r\n".
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
work=$(mktemp -d /tmp/hc-h2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf '\n\n\n' > "$work/f.txt"
( cd "$work" && "$RG_BIN" 'x?' --crlf --color always f.txt ) > "$work/out.bin" 2> "$work/err.txt"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "rg exited $rc (expected 0); stderr:" >&2
    head -5 "$work/err.txt" >&2
    exit 1
fi
expected="0d0a0d0a0d0a"   # \r\n\r\n\r\n
got=$(od -An -tx1 "$work/out.bin" | tr -d ' \n')
if [ "$got" != "$expected" ]; then
    echo "unexpected stdout bytes (got $got)" >&2
    exit 1
fi
exit 0