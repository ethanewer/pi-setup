#!/bin/bash
# Reproduction checker for marlinespike-wake.
#
# Contract (matches the task instruction):
#   cd /app/src; run `node bin/prettier.js /app/repro/input.scss`; compare
#   stdout with /app/repro/expected.scss; exit 0 iff byte-identical, else
#   exit non-zero and print a readable diff.
#
# On the pre-fix tree this FAILS (the condition is split right after `==`);
# on a correctly fixed tree it PASSES.
set -u
cd /app/src || exit 1

node bin/prettier.js /app/repro/input.scss > /tmp/marlinespike-repro.out 2> /tmp/marlinespike-repro.err || {
    echo "prettier CLI exited non-zero; stderr:"
    cat /tmp/marlinespike-repro.err
    exit 1
}

if ! cmp -s /tmp/marlinespike-repro.out /app/repro/expected.scss; then
    echo "formatted output does not match expected.scss:"
    diff -u /app/repro/expected.scss /tmp/marlinespike-repro.out | head -30
    exit 1
fi

echo "reproduction passes: CLI output matches expected.scss byte-for-byte"
exit 0