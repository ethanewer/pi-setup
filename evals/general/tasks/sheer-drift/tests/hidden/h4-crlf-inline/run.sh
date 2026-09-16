#!/bin/bash
# Hidden case h4: the CRLF-mode COLORED OUTPUT on a real CRLF file with a
# NON-EMPTY match (input the upstream test does not use: the upstream test
# only checks that an empty line prints non-empty output). This case pins the
# byte-exact colored output of the line-terminator trim: when --crlf handling
# trims the carriage return before colouring, the printable byte sequence for
# each line is "...o\r\n"; a "fix" that merely deletes the CR-trim branch
# (which byte-identically masks the crash on LF-only inputs) instead emits a
# stray "\r" before the terminator ("...o\r\r\n") and fails this case.
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
work=$(mktemp -d /tmp/hc-h4.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'hello\r\nworld\r\n' > "$work/f.txt"
( cd "$work" && "$RG_BIN" 'ell' --crlf --color always f.txt ) > "$work/out.bin" 2> "$work/err.txt"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "rg exited $rc (expected 0); stderr:" >&2
    head -5 "$work/err.txt" >&2
    exit 1
fi
expected="681b5b306d1b5b316d1b5b33316d656c6c1b5b306d6f0d0a"
got=$(od -An -tx1 "$work/out.bin" | tr -d ' \n')
if [ "$got" != "$expected" ]; then
    echo "unexpected stdout bytes (got $got)" >&2
    exit 1
fi
exit 0