#!/bin/bash
# Hidden case (b): -x exec mode (the single-command job loop -- fatal errors
# must return ExitCode::GeneralError instead of panicking the process from
# inside the walker).
# A --full-path search with -x whose working directory is removed mid-walk
# must not panic: exit status 1 with the filesystem error reported, or a
# graceful exit 0. exec modes never print the matches themselves, so a
# zero-output graceful finish is acceptable. The tree is smaller here (80k
# files): in exec mode the resolution is paced by the drain of the bounded
# channel, so the walk is still resolving when the cwd is removed.
set -u

CASE_FILES=80000
. /tests/hidden/lib.sh

[ -x "$FD_BIN" ] || { echo "FAIL: fd binary not found at $FD_BIN" >&2; exit 1; }

setup_search_tree
trap 'cleanup_case; stop_deleter' EXIT
rm -f "$OUT_FILE" "$ERR_FILE"

start_deleter
set +e
"$FD_BIN" --full-path --show-errors -j 1 . link -x true >"$OUT_FILE" 2>"$ERR_FILE"
rc=$?
set -e
stop_deleter
out=$(cat "$OUT_FILE")
err=$(cat "$ERR_FILE")

echo "== case-exec: fd --full-path -x true with cwd removed mid-walk =="
echo "fd exit status: $rc"
if ! assert_cwd_removed; then exit 1; fi
if ! assert_graceful_ok "$rc" "$out" "$err" 0; then exit 1; fi
exit 0