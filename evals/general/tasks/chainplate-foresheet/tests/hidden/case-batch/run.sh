#!/bin/bash
# Hidden case (c): -X exec-batch mode (the batch path -- the third consumer
# arm of WorkerResult, which collects results before executing them).
# A --full-path search with -X whose working directory is removed mid-walk
# must not panic: exit status 1 with the filesystem error reported, or a
# graceful exit 0.
set -u

CASE_FILES=80000
. /tests/hidden/lib.sh

[ -x "$FD_BIN" ] || { echo "FAIL: fd binary not found at $FD_BIN" >&2; exit 1; }

setup_search_tree
trap 'cleanup_case; stop_deleter' EXIT
rm -f "$OUT_FILE" "$ERR_FILE"

start_deleter
set +e
"$FD_BIN" --full-path --show-errors -j 1 . link -X true >"$OUT_FILE" 2>"$ERR_FILE"
rc=$?
set -e
stop_deleter
out=$(cat "$OUT_FILE")
err=$(cat "$ERR_FILE")

echo "== case-batch: fd --full-path -X true with cwd removed mid-walk =="
echo "fd exit status: $rc"
if ! assert_cwd_removed; then exit 1; fi
if ! assert_graceful_ok "$rc" "$out" "$err" 0; then exit 1; fi
exit 0