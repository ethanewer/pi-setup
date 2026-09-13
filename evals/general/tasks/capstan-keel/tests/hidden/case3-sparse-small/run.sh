#!/bin/bash
# Hidden case 3: a sparse file and a small file.  The pre-fix code reports the
# logical length (512 MiB for the sparse file's hole); a correct account sums
# the allocated blocks, which the helper computes from st_blocks (0 for a
# fully-sparse file, one whole block for the small file on a 4 KiB-block
# filesystem).
set -u

WORK="$(mktemp -d /tmp/hc3.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cache" "$WORK/home"

truncate -s 536870912 "$WORK/cache/sparse.bin"    # 512 MiB hole, ~0 blocks
printf 'x%.0s' {1..1000} > "$WORK/cache/small.bin"  # 1000 B, one block allocated

EXPECTED="$(python3 /tests/hidden/_lib/expect.py "$WORK" cache/sparse.bin cache/small.bin)" \
  || { echo "setup error: expected-figure computation failed" >&2; exit 1; }

CLEAN_OUT="$WORK/clean.out"
env HOME="$WORK/home" UV_CACHE_DIR="$WORK/cache" \
  /app/src/target/debug/uv cache clean > "$CLEAN_OUT" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL(case3): uv cache clean exited $rc" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

if [ -e "$WORK/cache/sparse.bin" ] || [ -e "$WORK/cache/small.bin" ]; then
  echo "FAIL(case3): cache entries were not removed" >&2
  exit 1
fi

ACTUAL="$(grep -oE '\([0-9.]+[A-Za-z]*B\)' "$CLEAN_OUT" | tail -1)"
if [ -z "$ACTUAL" ]; then
  echo "FAIL(case3): no 'Removed N files (SIZE)' line in uv output:" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

echo "case3: expected $EXPECTED got ($ACTUAL)"
[ "$ACTUAL" = "$EXPECTED" ]