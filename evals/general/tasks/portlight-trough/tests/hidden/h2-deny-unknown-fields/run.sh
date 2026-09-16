#!/bin/bash
# Hidden case h2: deny_unknown_fields is now honoured. With the attribute set on
# an adjacently tagged enum, an extra key must be rejected deliberately (assert
# an error), while a clean map still deserializes. The upstream regression test
# never exercises deny_unknown_fields on this code path. Must pass on the fixed
# tree.
set -u
cd /app/src || exit 1
cp "$(dirname "$0")/h2_strict.rs" test_suite/tests/h2_strict.rs || exit 1
if ! cargo test -p serde_test_suite --test h2_strict > /tmp/h2.out 2>&1; then
    tail -25 /tmp/h2.out >&2
    exit 1
fi
grep -q "test result: ok" /tmp/h2.out || { tail -15 /tmp/h2.out >&2; exit 1; }
exit 0
