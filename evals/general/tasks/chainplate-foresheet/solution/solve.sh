#!/bin/bash
# Oracle for chainplate-foresheet: applies the upstream fix to the fd checkout
# at /app/src (error propagation instead of the panicking .expect for the
# --full-path current-directory resolution, plus a WorkerResult::FatalError
# variant handled in the receiver loop, the -x job loop and the -X batch
# path), rebuilds, and re-runs the reproduction and the project's own
# regression test from the tree.
set -e

SRC=/app/src

if ! git -C "$SRC" apply --check /solution/fix.patch 2>/dev/null; then
  echo "fix.patch does not apply cleanly; is the tree already fixed or modified?" >&2
  git -C "$SRC" status --porcelain | head
  exit 1
fi
git -C "$SRC" apply /solution/fix.patch

echo "== resulting diff (stat) =="
git -C "$SRC" diff --stat
git -C "$SRC" diff | sed 's/^/    /' | head -60

echo "== rebuild =="
cd "$SRC" && cargo build

echo "== reproduction after the fix (probe must report fixed behaviour) =="
/app/probe_cwd_removed.sh

echo "== the project's own regression test for this bug =="
cargo test full_path_search_returns_error_for_invalid_cwd

echo "== oracle done =="