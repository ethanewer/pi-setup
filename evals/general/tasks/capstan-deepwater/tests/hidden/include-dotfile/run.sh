#!/bin/bash
# Hidden case: an INCLUSION glob selecting a file whose name ends with a
# dot. On the unfixed tree the glob silently matches nothing (no output,
# exit status 1); after the fix the file must be listed and rg must exit 0.
set -e
unset RIPGREP_CONFIG_PATH
mkdir -p fx
: > fx/mubla
: > fx/mubla.
: > fx/plain
cd fx
exec /app/src/target/debug/rg --sort=path --files -g 'mubla.' .