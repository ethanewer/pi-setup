#!/bin/bash
# Oracle for lintel-winch (executes-deliverable).
# Installs the real solver as the crate's library root module and proves the
# whole thing green with the shipped test suite.  Never reads /tests.
set -u

CRATE=/app/lwrecord/

if [ ! -f "$CRATE"Cargo.toml ]; then
  echo "missing crate /app/lwrecord/" >&2
  exit 1
fi

cp /solution/solver.rs "$CRATE"src/lib.rs

cd "$CRATE" || exit 1
cargo test --offline
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "cargo test failed (rc=$rc)" >&2
  exit 1
fi

echo "SOLVE_DONE"
exit 0
