#!/bin/bash
# Hidden case h4: selective whitelist - '.foo.txt' is whitelisted, but a
# second hidden file '.junk' is NOT and must stay hidden. On the unfixed
# tree the prefix mangling drops even the whitelisted file (empty output);
# a sloppy 'fix' that globally disables hidden-file skipping would wrongly
# list './.junk' too. The correct fix lists exactly './.foo.txt' and exits 0.
unset RIPGREP_CONFIG_PATH
export HOME=$PWD
rm -rf pw && mkdir -p pw/subdir
printf 'wanted\n' > pw/subdir/.foo.txt
printf 'unwanted\n' > pw/subdir/.junk
printf '!.foo.txt\n' > pw/.ignore
cd pw/subdir
exec /app/src/target/debug/rg --no-config --sort=path --files .