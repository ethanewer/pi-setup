#!/bin/bash
# Oracle for capstan-brackish: applies the upstream one-line fix to the fd
# checkout at /app/src, rebuilds, re-runs the reproduction, and runs the
# project's own regression test from the tree.
set -e

SRC=/app/src

python3 /solution/fix_time.py "$SRC/src/filter/time.rs"

echo "== resulting diff =="
git -C "$SRC" diff --stat
git -C "$SRC" diff | sed 's/^/    /' | head -30

echo "== rebuild =="
cd "$SRC" && cargo build

echo "== reproduction output after the fix =="
/app/probe_out_of_range_ts.sh

echo "== CLI check: --changed-before and --changed-within, out of range =="
set +e
for args in "--changed-before @18446744073709551615" "--changed-within @18446744073709551615"; do
  out=$(target/debug/fd $args . /tmp 2>&1)
  code=$?
  echo "fd $args -> exit $code"
  printf '%s\n' "$out" | head -1
  [ "$code" -eq 1 ] || { echo "FAIL: expected exit 1, got $code" >&2; exit 1; }
  printf '%s' "$out" | grep -q "not a valid date or duration" || { echo "FAIL: missing graceful error" >&2; exit 1; }
done
set -e

echo "== project's own regression test =="
cargo test out_of_range_unix_timestamp_is_rejected

echo "== oracle done =="