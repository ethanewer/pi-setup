#!/bin/bash
# Reference reproduction for flotsam-fairway; the oracle installs this as
# /app/reproduce.sh. Two-sided: it runs the engine it is given (first
# argument, default the repaired checkout) against the two faces of the bug
# (a plain %c of byte 255 and a string function applied to such a result),
# prints the engine's raw output, and exits 0 iff the engine shows the fixed
# behaviour: a clean user-facing error containing "Invalid UTF8 produced by
# format string" and no INTERNAL error. A script that satisfies this contract
# necessarily fails (non-zero) against the pre-fix engine, which never
# produces that message.
set -u
ENGINE=${1:-/app/src/build/release/duckdb}

q1="SELECT printf('%c', 255);"
q2="SELECT lower(printf('%c', 255));"

out1=$("$ENGINE" -c "$q1" 2>&1)
out2=$("$ENGINE" -c "$q2" 2>&1)
printf '%s\n%s\n' "$out1" "$out2"

all=$(printf '%s\n%s\n' "$out1" "$out2")

if ! printf '%s\n' "$all" | grep -q "Invalid UTF8 produced by format string"; then
  exit 1
fi
if printf '%s\n' "$all" | grep -q "INTERNAL Error"; then
  exit 1
fi
exit 0