#!/bin/bash
# Hidden case 2: a mixed cache - one entry is a hard link to an external file
# (frees nothing), the other is an independent regular file (frees its
# allocated blocks: exactly 1 MiB for a fully-allocated 1 MiB file).  The
# pre-fix code sums logical lengths (6 MiB).
set -u

WORK="$(mktemp -d /tmp/hc2.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cache" "$WORK/home"

head -c 5242880 /dev/zero > "$WORK/retained.bin"          # 5 MiB, stays on disk
ln "$WORK/retained.bin" "$WORK/cache/hardlinked.bin"      # frees 0
head -c 1048576 /dev/zero > "$WORK/cache/regular.bin"     # frees 1 MiB

EXPECTED="$(python3 /tests/hidden/_lib/expect.py "$WORK" cache/hardlinked.bin cache/regular.bin)" \
  || { echo "setup error: expected-figure computation failed" >&2; exit 1; }

CLEAN_OUT="$WORK/clean.out"
env HOME="$WORK/home" UV_CACHE_DIR="$WORK/cache" \
  /app/src/target/debug/uv cache clean > "$CLEAN_OUT" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL(case2): uv cache clean exited $rc" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

if [ -e "$WORK/cache/hardlinked.bin" ] || [ -e "$WORK/cache/regular.bin" ]; then
  echo "FAIL(case2): cache entries were not removed" >&2
  exit 1
fi

ACTUAL="$(grep -oE '\([0-9.]+[A-Za-z]*B\)' "$CLEAN_OUT" | tail -1)"
if [ -z "$ACTUAL" ]; then
  echo "FAIL(case2): no 'Removed N files (SIZE)' line in uv output:" >&2
  cat "$CLEAN_OUT" | sed 's/^/    /' >&2
  exit 1
fi

echo "case2: expected $EXPECTED got ($ACTUAL)"
[ "$ACTUAL" = "$EXPECTED" ]