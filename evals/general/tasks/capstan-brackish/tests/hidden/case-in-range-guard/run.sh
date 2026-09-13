#!/bin/bash
# Hidden case (guard against over-correction): the huge but in-range
# timestamp @9223372036854775807 (i64::MAX) must keep working normally after
# the fix -- it must not be rejected, must not panic, and the search must
# behave as before (every ordinary file is older, so it is listed).
# Also guards a normal small '@' timestamp on --changed-within.
#
# CLI shape: `fd [OPTIONS] [PATTERN] [PATH]...` -- first positional is the
# search pattern ("." matches everything), second is the search directory.
set -u

FD=/app/src/target/debug/fd
[ -x "$FD" ] || { echo "FAIL: fd binary not found at $FD" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
touch "$WORK/alpha.txt" "$WORK/beta.txt"

out=$("$FD" --changed-before @9223372036854775807 . "$WORK" 2>&1)
code=$?
[ "$code" -eq 0 ] || { echo "FAIL: --changed-before @9223372036854775807 exited $code instead of 0" >&2; printf '%s\n' "$out" | head -4 >&2; exit 1; }
printf '%s' "$out" | grep -q "panicked" && { echo "FAIL: output contains a panic" >&2; exit 1; }
printf '%s' "$out" | grep -q "not a valid date or duration" && { echo "FAIL: the huge in-range timestamp was rejected" >&2; exit 1; }
printf '%s' "$out" | grep -q "alpha.txt" || { echo "FAIL: --changed-before @9223372036854775807 listed no files (output: $(printf '%s' "$out" | head -3))" >&2; exit 1; }

out=$("$FD" --changed-within @1707723412 . "$WORK" 2>&1)
code=$?
[ "$code" -eq 0 ] || { echo "FAIL: --changed-within @1707723412 (a normal in-range timestamp) exited $code instead of 0" >&2; printf '%s\n' "$out" | head -4 >&2; exit 1; }
printf '%s' "$out" | grep -q "panicked" && { echo "FAIL: output contains a panic" >&2; exit 1; }

echo "ok: in-range '@' timestamps keep working normally"
exit 0