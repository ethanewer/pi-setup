#!/usr/bin/env bash
# Install the wigeon vendored dependency into .cache_deps (cache-miss only).
set -euo pipefail
mkdir -p .cache_deps
rm -rf .cache_deps/sndlib
cp -r ci/vendor/sndlib .cache_deps/sndlib
printf 'sndlib==0.9.0\n' > .cache_deps/DEPENDENCIES
echo "vendored dependencies installed (sndlib 0.9.0)"
