#!/bin/bash
# Hidden case: a plain FILE whose name ends with a dot, excluded by a
# negated basename glob. On the unfixed tree the glob is silently ignored and
# mubla. stays in the listing; after the fix it must be excluded. --sort=path
# keeps the listing order deterministic, and an explicit path argument keeps
# rg's stdin heuristic out of the picture.
set -e
unset RIPGREP_CONFIG_PATH
mkdir -p fx
: > fx/mubla
: > fx/mubla.
: > fx/plain
cd fx
exec /app/src/target/debug/rg --sort=path --files -g '!mubla.' .