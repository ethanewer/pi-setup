#!/bin/bash
# probe_cache_accounting.sh - reproduce uv's cache space-accounting bug.
#
# The `uv` binary lives at /app/src/target/debug/uv (built from the checkout
# at /app/src).  This script builds a small fake cache directory, runs
# `uv cache clean` against it, and prints both what uv REPORTS and what the
# filesystem metadata says the deletion actually frees.
#
# Usage:
#   /app/probe_cache_accounting.sh            # hard-link scenario (default)
#   /app/probe_cache_accounting.sh sparse     # sparse-file scenario
#
# The two numbers disagree for every cached file whose byte length does not
# match its allocation: hard-linked files (the length counts twice even though
# the storage is shared) and sparse files (the hole is charged as if it were
# data).

set -u

UV_BIN="${UV_BIN:-/app/src/target/debug/uv}"
SCENARIO="${1:-hardlink}"

WORK="$(mktemp -d /tmp/cx.XXXXXX)"
mkdir -p "$WORK/cache" "$WORK/home"
export HOME="$WORK/home"
export UV_CACHE_DIR="$WORK/cache"

echo "== scenario: $SCENARIO =="

case "$SCENARIO" in
  hardlink)
    # A 1 MiB fully-allocated file that lives OUTSIDE the cache and stays on
    # disk; the cache entry is a hard link to it.
    head -c 1048576 /dev/zero > "$WORK/retained.bin"
    ln "$WORK/retained.bin" "$WORK/cache/cached.bin"
    ;;
  sparse)
    # A 512 MiB sparse file (the hole occupies no disk blocks) inside the
    # cache.
    truncate -s 536870912 "$WORK/cache/sparse.bin"
    ;;
  *)
    echo "unknown scenario: $SCENARIO" >&2
    exit 2
    ;;
esac

echo
echo "== metadata =="
python3 - "$WORK/cache" <<'PY'
import os, sys
for root, dirs, files in os.walk(sys.argv[1]):
    for f in sorted(files):
        p = os.path.join(root, f)
        st = os.lstat(p)
        print(f"{p}: logical_len={st.st_size} blocks512={st.st_blocks} nlink={st.st_nlink} "
              f"allocated_bytes={st.st_blocks * 512}")
PY

echo
echo "== uv cache clean (stderr shown) =="
"$UV_BIN" cache clean
rc=$?
echo "(exit code $rc)"

echo
echo "== files remaining under the cache dir =="
find "$WORK/cache" -type f 2>/dev/null | sort || true

rm -rf "$WORK"
exit "$rc"