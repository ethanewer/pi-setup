#!/bin/bash
# capstan-brackish probe: reproduce the user-visible crash.
#
# Runs the built fd binary with an out-of-range '@' Unix timestamp and
# reports whether the bug is present:
#   exit 1 (and a panic on stderr) : bug reproduced
#   exit 0 (graceful message)      : bug fixed
#
# CLI shape: `fd [OPTIONS] [PATTERN] [PATH]...` -- the first positional is
# the search pattern, so we pass a catch-all pattern "." and the search
# directory as the second positional.
set -u

FD=/app/src/target/debug/fd
if [ ! -x "$FD" ]; then
  echo "the fd binary is not built yet; build it first with:"
  echo "  cd /app/src && cargo build"
  exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
touch "$WORK/alpha.txt"

out=$("$FD" --changed-before @18446744073709551615 . "$WORK" 2>&1)
code=$?

if [ "$code" -eq 101 ] || printf '%s' "$out" | grep -q "panicked"; then
  echo "BUG REPRODUCED: fd panics on an out-of-range '@' timestamp (exit $code):"
  printf '%s\n' "$out" | head -4
  exit 1
elif [ "$code" -eq 1 ]; then
  echo "OK: fd rejects the out-of-range timestamp gracefully (exit 1):"
  printf '%s\n' "$out" | head -2
  exit 0
else
  echo "unexpected: fd exited with $code; output was:"
  printf '%s\n' "$out"
  exit 3
fi