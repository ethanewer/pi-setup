#!/bin/bash
# Hidden case h3: the same defect reached through STDIN instead of a file
# argument (input mechanism the upstream test does not use). A blank line in
# a three-line stdin stream panics the parent-commit binary (rc 101); the
# repaired binary must exit 0 and print exactly "a\r\n\r\nb\r\n".
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
work=$(mktemp -d /tmp/hc-h3.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
( cd "$work" && printf 'a\n\nb\n' | "$RG_BIN" 'x?' --crlf --color always ) > "$work/out.bin" 2> "$work/err.txt"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "rg exited $rc (expected 0); stderr:" >&2
    head -5 "$work/err.txt" >&2
    exit 1
fi
expected="610d0a0d0a620d0a"   # a\r\n\r\nb\r\n
got=$(od -An -tx1 "$work/out.bin" | tr -d ' \n')
if [ "$got" != "$expected" ]; then
    echo "unexpected stdout bytes (got $got)" >&2
    exit 1
fi
exit 0