#!/bin/bash
# Hidden case (a): default print mode (the receiver loop).
# A --full-path search whose working directory is removed mid-walk must not
# panic: it must either abort with exit status 1 and report the filesystem
# error (--show-errors) or finish normally with exit status 0 and matches
# produced. On the buggy tree this run exits 101 with "thread '<unnamed>'
# panicked at src/walk.rs:529:26".
set -u

. /tests/hidden/lib.sh

[ -x "$FD_BIN" ] || { echo "FAIL: fd binary not found at $FD_BIN" >&2; exit 1; }

setup_search_tree
trap 'cleanup_case; stop_deleter' EXIT
rm -f "$OUT_FILE" "$ERR_FILE"

start_deleter
set +e
"$FD_BIN" --full-path --show-errors -j 1 . link >"$OUT_FILE" 2>"$ERR_FILE"
rc=$?
set -e
stop_deleter
out=$(cat "$OUT_FILE")
err=$(cat "$ERR_FILE")

echo "== case-stream: fd --full-path with cwd removed mid-walk (default print mode) =="
echo "fd exit status: $rc"
if ! assert_cwd_removed; then exit 1; fi
if ! assert_graceful_ok "$rc" "$out" "$err" 1; then exit 1; fi
exit 0