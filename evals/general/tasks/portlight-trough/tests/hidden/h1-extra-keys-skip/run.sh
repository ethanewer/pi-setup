#!/bin/bash
# Hidden case h1: tolerant skipping of heterogeneous extra keys. Exercises the
# same adjacently-tagged-enum code path as the upstream regression test but from
# inputs it does not use: map- and sequence-valued extra keys, struct and tuple
# variants, and content-before-tag orderings. Must pass on the fixed tree.
set -u
cd /app/src || exit 1
cp "$(dirname "$0")/h1_extra.rs" test_suite/tests/h1_extra.rs || exit 1
if ! cargo test -p serde_test_suite --test h1_extra > /tmp/h1.out 2>&1; then
    tail -25 /tmp/h1.out >&2
    exit 1
fi
grep -q "test result: ok" /tmp/h1.out || { tail -15 /tmp/h1.out >&2; exit 1; }
exit 0
