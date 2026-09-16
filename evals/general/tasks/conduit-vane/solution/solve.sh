#!/usr/bin/env bash
# Oracle for conduit-vane.
#
# Implements the resume capability required by docs/INTEGRATION.md in the
# shipped workspace: drops the resume module into veldt-transport, registers
# it in the crate root, and proves the workspace still builds and tests
# green. The implementation is a real one (resume.rs); nothing here reads
# /tests and nothing hardcodes a consumer expectation.
set -eu

WS=/app/workspace/crates/veldt-transport

cp /solution/resume.rs "$WS/src/resume.rs"

if ! grep -q "pub mod resume;" "$WS/src/lib.rs"; then
    printf '\npub mod resume;\n' >> "$WS/src/lib.rs"
fi

cd /app/workspace
cargo build --workspace --offline
cargo test --workspace --offline

echo "oracle: resume capability integrated, workspace green"
echo "git:" && git log --oneline | head -5