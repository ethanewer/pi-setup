#!/bin/bash
# Oracle for merlon-cleat.
#
# Real solver: replaces the allocation-happy encoder of the Pennant frame
# library with an allocation-free implementation that writes the frame
# directly into the caller's buffer, then proves the crate still builds and
# its whole test suite stays green. The graded artifacts (/app/pennant) are
# left in their improved state for the verifier to exercise: the hidden
# consumers compile unchanged against this crate and the benchmark measures
# the hot loop, so the oracle must make the real optimization, not fake it.
set -eu

cp /solution/fixed/src/codec.rs /app/pennant/src/codec.rs

cd /app/pennant
cargo test --offline >/tmp/oracle-cargo-test.log 2>&1
grep -q 'test result: ok' /tmp/oracle-cargo-test.log

echo "oracle: allocation-free encoder installed and crate test suite is green"
exit 0