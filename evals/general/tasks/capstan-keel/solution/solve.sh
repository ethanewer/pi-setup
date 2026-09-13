#!/bin/bash
# Oracle for capstan-keel: fixes the cache space-accounting bug in the real
# uv checkout at /app/src, rebuilds the binary, proves the CLI-visible
# symptom changed, and keeps the crate's own unit tests green.
set -e

echo "== before: what the buggy tree reports =="
/app/probe_cache_accounting.sh hardlink
echo
echo "== before: sparse scenario =="
/app/probe_cache_accounting.sh sparse

echo
echo "== applying the fix =="
python3 /solution/apply_fix.py

echo
echo "== rebuilding the uv binary =="
cd /app/src
cargo build -p uv

echo
echo "== after: hard-link scenario =="
/app/probe_cache_accounting.sh hardlink
echo
echo "== after: sparse scenario =="
/app/probe_cache_accounting.sh sparse

echo
echo "== the crate's own unit tests stay green =="
cd /app/src
cargo test -p uv-cache -q

echo
echo "== tree status (expect only the three fixed sources) =="
git status --porcelain