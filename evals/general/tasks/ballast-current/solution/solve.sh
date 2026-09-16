#!/bin/bash
# Oracle for ballast-current: applies the minimal upstream fix to the uv
# checkout at /app/src (make the cache-policy length guard overflow-safe),
# then rebuilds and runs the project's own regression test against the
# repaired tree.
set -euo pipefail

python3 /solution/fix_cached_client.py /app/src/crates/uv-client/src/cached_client.rs

echo "== rebuilding + running the upstream regression test =="
cd /app/src
cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact

echo "== offline part of the project's own integration suite =="
cargo test -p uv-client --test it -- cached_client proxy ssl_certs user_agent_version