#!/usr/bin/env bash
# Install the curlew vendored dependency into .vendor (cache-miss only).
set -euo pipefail
mkdir -p .vendor
rm -rf .vendor/gridlib
cp -r ci/vendor/gridlib .vendor/gridlib
printf 'gridlib==0.4.1\n' > .vendor/DEPENDENCIES
echo "vendored dependencies installed (gridlib 0.4.1)"
