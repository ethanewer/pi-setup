#!/bin/bash
# Reproduction driver for the glob-matching option-cache bug.
#
# Compiles the glob-matcher implementation and its path-separator helper
# straight out of /app/src (so your edits take effect on the next run)
# with the toolchain at /opt/tsapp, then makes two calls with the SAME glob
# in one process:
#
#   first call:  no options  -> a dotfile must match (dot matching is on by
#                               default)
#   second call: {dot:false} -> the dotfile must NOT match
#
# Prints "<first> <second>" and then behaves as follows:
#   "true true"   -> exit 1: BUG PRESENT (the second call reused the matcher
#                    built for the first call instead of honouring dot:false)
#   "true false"  -> exit 0: the bug is fixed
#   anything else -> exit 2: unexpected behaviour
#
# Usage: bash /app/repro.sh
set -euo pipefail
SRC=/app/src/packages/jest-util/src
TS=/opt/tsapp
RUN=$(mktemp -d /tmp/repro.XXXXXX)
trap 'rm -rf "$RUN"' EXIT

cp "$SRC/globsToMatcher.ts" "$SRC/replacePathSepForGlob.ts" "$RUN/"
cp "$TS/tsconfig.json" "$TS/jest.config.json" "$RUN/"
ln -s "$TS/node_modules" "$RUN/node_modules"

cat > "$RUN/repro.ts" <<'EOF'
import globsToMatcher from './globsToMatcher';

const globs = ['*.dotoption.js'];
const first = globsToMatcher(globs)('.hidden.dotoption.js');
const second = globsToMatcher(globs, {dot: false})('.hidden.dotoption.js');
console.log(`${first} ${second}`);
if (first && second) {
  console.error(
    'BUG PRESENT: the second call, made with {dot: false}, still matched the ' +
    'dotfile. The matcher built for the first call was reused instead of ' +
    'honouring the caller\u2019s options.',
  );
  process.exit(1);
}
if (!first || second) {
  console.error('Unexpected results: expected "true false".');
  process.exit(2);
}
console.log(
  'OK: the second call honoured {dot: false} and did not match the dotfile.',
);
EOF

cd "$RUN"
"$TS/node_modules/.bin/tsc" -p tsconfig.json
node out/repro.js