#!/bin/bash
# Hidden case h3: a whitelist rule for a whole hidden DIRECTORY
# ('!.cache/' with trailing slash) re-includes everything inside it. The
# walker's prefix-mangling drops the whole hidden directory on the unfixed
# tree ('./.cache/x' silently missing, exit 1); the fixed tree must list
# './.cache/x' and exit 0.
unset RIPGREP_CONFIG_PATH
export HOME=$PWD
rm -rf pw && mkdir -p pw/subdir/.cache
printf 'cached\n' > pw/subdir/.cache/x
printf '!.cache/\n' > pw/.ignore
cd pw/subdir
exec /app/src/target/debug/rg --no-config --sort=path --files .