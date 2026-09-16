#!/bin/bash
# Hidden case: SEARCH MODE (not --files) with a negation glob for a
# trailing-dot directory. On the unfixed tree the glob is silently ignored
# and the search descends into grxv./, printing a match line for
# grxv./foo as well; after the fix only grxv/foo:secret is printed. An
# explicit path argument keeps rg's stdin heuristic out of the picture.
set -e
unset RIPGREP_CONFIG_PATH
mkdir -p fx/grxv fx/grxv.
printf 'secret\n' > fx/grxv/foo
printf 'secret\n' > fx/grxv./foo
cd fx
exec /app/src/target/debug/rg --sort=path -g '!grxv./' secret .