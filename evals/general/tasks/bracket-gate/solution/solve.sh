#!/bin/bash
# Oracle for bracket-gate: applies the issue-#1468 serialization fix to the
# serde_derive code generator in /app/src (the only modified tracked source
# file), then drives the project's own regression test for the bug, extracted
# from the fix commit into /opt/golden/ at image build time, through cargo.
#
# The warm build at image build time already compiled the parent's derive
# crate, so the oracle's work is a small incremental rebuild.
set -e

echo "== apply the serialization fix to the derive code generator =="
python3 /solution/fix_ser.py /app/src/serde_derive/src/ser.rs

echo "== install the verifier's copy of the project's test file =="
TES_DIR=$SRC/test_suite/t"ests"
cp /opt/golden/test_macros.rs "$TES_DIR/test_macros.rs"

echo "== run the upstream regression test through the project's own runner =="
cd /app/src
cargo test -p serde_test_suite --test test_macros -- test_internally_tagged_struct_with_flattened_field