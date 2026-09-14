#!/bin/bash
# Hidden case h2: a `!.*` whitelist re-includes every hidden file; a plain
# visible file must also still be listed. Search starts in the subdirectory
# with the path spelled '.', --sort=path makes the listing deterministic.
# Unfixed tree: hidden files silently dropped (only './seen.txt' listed);
# fixed tree must list all three in byte order and exit 0.
unset RIPGREP_CONFIG_PATH
export HOME=$PWD
rm -rf pw && mkdir -p pw/subdir
printf 'alpha\n' > pw/subdir/.foo.txt
printf 'beta\n' > pw/subdir/.bar.txt
printf 'plain\n' > pw/subdir/seen.txt
printf '!.*\n' > pw/.ignore
cd pw/subdir
exec /app/src/target/debug/rg --no-config --sort=path --files .