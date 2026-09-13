#!/bin/bash
# Run any single jest test file against the glob-matcher sources currently
# in /app/src, using the toolchain at /opt/tsapp (typescript compile, then
# the published jest test runner).
#
# Usage: bash /app/run-test.sh <path-to-a-*.test.ts>
#   e.g. bash /app/run-test.sh /app/src/packages/jest-util/src/__tests__/globsToMatcher.test.ts
#
# The file you pass is copied into a scratch layout where the tree's
# glob-matcher implementation and its path-separator helper live next to a
# __tests__/ directory, exactly as they do in the real repository, so
# relative imports inside the test file keep resolving. tsc typechecks the
# whole scratch tree first (strict); jest then runs it.
#
# Exit status is 0 exactly when the compile and every test pass.
set -euo pipefail
TESTFILE=${1:?usage: /app/run-test.sh <test-file.ts>}
SRC=/app/src/packages/jest-util/src
TS=/opt/tsapp
RUN=$(mktemp -d /tmp/run-test.XXXXXX)
trap 'rm -rf "$RUN"' EXIT

mkdir -p "$RUN/__tests__"
cp "$SRC/globsToMatcher.ts" "$SRC/replacePathSepForGlob.ts" "$RUN/"
cp "$TS/tsconfig.json" "$TS/jest.config.json" "$RUN/"
ln -s "$TS/node_modules" "$RUN/node_modules"
cp "$TESTFILE" "$RUN/__tests__/"

cd "$RUN"
"$TS/node_modules/.bin/tsc" -p tsconfig.json
"$TS/node_modules/.bin/jest" out/__tests__/