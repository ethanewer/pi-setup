#!/bin/bash
# Hidden case: a NESTED directory whose name ends with a dot, excluded with
# a '**/'-prefixed negation glob. The upstream regression test only covers a
# top-level trailing-dot directory; this exercises the same broken
# file-name-extraction path one level deep. On the unfixed tree the glob is
# silently ignored and the files under a/nxq./ stay listed.
set -e
unset RIPGREP_CONFIG_PATH
mkdir -p fx/a/nxq. fx/a/cc
: > fx/a/nxq./x
: > fx/a/nxq./x.
: > fx/a/cc/x
cd fx
exec /app/src/target/debug/rg --sort=path --files -g '!**/nxq./' .