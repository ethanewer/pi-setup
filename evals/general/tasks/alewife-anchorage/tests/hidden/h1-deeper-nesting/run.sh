#!/bin/bash
# Hidden case h1: deeper nesting - the whitelisted hidden file sits two
# levels below the ignore file, and the search starts in the innermost
# subdirectory with the path spelled '.'. Fails (empty, exit 1) on the
# unfixed tree; must list './.foo.txt' and exit 0 after the fix.
unset RIPGREP_CONFIG_PATH
export HOME=$PWD
rm -rf pw && mkdir -p pw/a/b
printf 'deep text\n' > pw/a/b/.foo.txt
printf '!.foo.txt\n' > pw/.ignore
cd pw/a/b
exec /app/src/target/debug/rg --no-config --sort=path --files .