#!/usr/bin/env bash
# Install the avocet vendored dependency into .deps (cache-miss only).
set -euo pipefail
mkdir -p .deps
rm -rf .deps/statlib
cp -r ci/vendor/statlib .deps/statlib
printf 'statlib==2.0.0\n' > .deps/DEPENDENCIES
echo "vendored dependencies installed (statlib 2.0.0)"
