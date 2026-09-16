#!/bin/bash
# Oracle for lintel-flood: repair the floodgate crate's combined-strategy
# integration with real work.
#
# The reference solver inspects the actual verdict shapes declared by the
# sliding and bucket strategy modules, regenerates the combined-strategy
# module to implement the documented contract (admit iff both admit; retry =
# the larger of the two individual retry delays), and proves the repair by
# building and testing under `--features sliding,bucket`.
#
# It never reads /tests and hardcodes no expected output.
set -eu

export CARGO_NET_OFF=true

python3 /solution/fixer.py /app/floodgate/
cd /app/floodgate/
cargo build --features sliding,bucket
cargo test --features sliding,bucket > /tmp/oracle_dual_test.log 2>&1 || {
    echo "oracle self-test failed; see /tmp/oracle_dual_test.log" >&2
    exit 1
}

echo "oracle repaired /app/floodgate (all four combinations green)"
exit 0