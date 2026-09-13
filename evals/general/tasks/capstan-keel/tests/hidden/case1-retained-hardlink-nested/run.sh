#!/bin/bash
# Hidden case 1: a hard-linked cache entry whose storage is shared BOTH with a
# surviving external file AND with a second cache entry, nested inside a
# subdirectory.  Deleting the cache content frees 0 bytes: the external file
# keeps the storage alive, so neither link inside the cache is ever the last
# one.  The pre-fix code reports both entries' logical length (6 MiB).
set -u

WORK="$(mktemp -d /tmp/hc1.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cache/nested" "$WORK/home"

head -c 3145728 /dev/zero > "$WORK/retained.bin"          # 3 MiB, stays on disk
ln "$WORK/retained.bin" "$WORK/cache/nested/cached.bin"   # link 2
ln "$WORK/retained.bin" "$WORK/cache/other.bin"           # link 3 (also in cache)

EXPECTED="$(python3 /tests/hidden/_lib/expect.py "$WORK" cache/nested/cached.bin cache/other.bin)" \
  || { echo "setup error: expected-figure computation failed" >&2; exit 1; }

CLEAN_OUT="$WORK/clean.out"
env HOME="$WORK/home" UV_CACHE_DIR="$WORK/cache" \
  /app/src/target/debug/uv cache clean > "$CLEAN_OUT" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL(case1): uv cache clean exited $rc" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

if [ -e "$WORK/cache/nested/cached.bin" ] || [ -e "$WORK/cache/other.bin" ]; then
  echo "FAIL(case1): cache entries were not removed" >&2
  exit 1
fi

ACTUAL="$(grep -oE '\([0-9.]+[A-Za-z]*B\)' "$CLEAN_OUT" | tail -1)"
if [ -z "$ACTUAL" ]; then
  echo "FAIL(case1): no 'Removed N files (SIZE)' line in uv output:" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

echo "case1: expected $EXPECTED got ($ACTUAL)"
[ "$ACTUAL" = "$EXPECTED" ]