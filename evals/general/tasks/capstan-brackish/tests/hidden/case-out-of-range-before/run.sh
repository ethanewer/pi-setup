#!/bin/bash
# Hidden case: --changed-before with an out-of-range '@' timestamp that the
# upstream regression test does not use (@9223372036854775808 = 2^63, which
# parses as u64 but cannot fit the internal time representation) must be
# rejected gracefully: exit 1, the ordinary "not a valid date or duration"
# error, and no panic.
#
# CLI shape: `fd [OPTIONS] [PATTERN] [PATH]...` -- first positional is the
# search pattern ("." matches everything), second is the search directory.
set -u

FD=/app/src/target/debug/fd
[ -x "$FD" ] || { echo "FAIL: fd binary not found at $FD" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
touch "$WORK/alpha.txt" "$WORK/beta.txt"

out=$("$FD" --changed-before @9223372036854775808 . "$WORK" 2>&1)
code=$?

[ "$code" -eq 1 ] || { echo "FAIL: expected exit 1, got $code (crash? output: $(printf '%s' "$out" | head -1))" >&2; exit 1; }
printf '%s' "$out" | grep -q "panicked" && { echo "FAIL: output contains a panic" >&2; printf '%s\n' "$out" | head -4 >&2; exit 1; }
printf '%s' "$out" | grep -q "not a valid date or duration" || { echo "FAIL: missing the graceful parse error; output: $(printf '%s' "$out" | head -2)" >&2; exit 1; }

echo "ok: --changed-before rejects @9223372036854775808 gracefully"
exit 0