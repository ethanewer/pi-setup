#!/bin/bash
# merlon-cleat fixture generator, run at image-build time.
#
# Materializes the /app/pennant git repository from the checked-in sources,
# building a plausible incremental history; proves the fixture is green by
# running its test suite; derives the pristine reference implementation at
# /opt/reference/pennant (the same v0.1 source, packaged under a different
# crate name so a benchmark binary can link BOTH implementations); and builds
# the malloc-family counting shim to /opt/libcountallocs.so.
#
# Everything here runs at build time with network available; the trial
# container is offline, which is why the crate must stay dependency-free.
set -eu

CRATE=/app/pennant
REF=/opt/reference/pennant

echo "== [1/5] crate files present =="
[ -f "$CRATE/Cargo.toml" ] || { echo "missing crate manifest"; exit 1; }

echo "== [2/5] build the git history =="
cd "$CRATE"
rm -f Cargo.lock
rm -rf .git
git init -q
git add Cargo.toml .gitignore README.md docs/
git commit -q -m "Project scaffold: crate metadata, README and protocol docs"
git add src/varint.rs src/lib.rs
git commit -q -m "Core types and the unsigned base-128 varint codec"
git add src/codec.rs src/decode.rs
git commit -q -m "Frame encoder and decoder for the Pennant wire format"
git add tests/
git commit -q -m "Wire-format and round-trip integration tests"
git log --oneline | tail -20

echo "== [3/5] build-time verification: fixture tests must be green =="
cargo test --offline >/tmp/boot-cargo-test.log 2>&1 || {
    echo "FIXTURE CRATE TESTS FAILED"; cat /tmp/boot-cargo-test.log; exit 1; }
grep -c 'test result: ok' /tmp/boot-cargo-test.log
git add src/bin/ Cargo.lock
git commit -q -m "pennpack CLI and lockfile pin" || echo "(no changes to commit)"

echo "== [4/5] derive the reference implementation =="
mkdir -p "$REF/src"
cp "$CRATE"/src/lib.rs "$CRATE"/src/varint.rs "$CRATE"/src/codec.rs "$CRATE"/src/decode.rs "$REF/src/"
cat > "$REF/Cargo.toml" <<'TOML'
[package]
name = "pennant-baseline"
version = "0.1.0"
edition = "2021"
description = "Pristine v0.1 pennant implementation (read-only benchmark reference)"

[lib]
path = "src/lib.rs"

[profile.release]
opt-level = 3
TOML
( cd "$REF" && cargo build --offline --release >/tmp/ref-boot.log 2>&1 ) || {
    echo "REFERENCE BUILD FAILED"; cat /tmp/ref-boot.log; exit 1; }
rm -rf "$REF/target"

echo "== [5/5] build the allocation-counting shim =="
gcc -shared -fPIC -O2 -o /opt/libcountallocs.so /app/toolchain/countallocs.c -ldl -lpthread
strip /opt/libcountallocs.so
chmod 755 /opt/libcountallocs.so
# smoke test: an interposed binary must still run
LD_PRELOAD=/opt/libcountallocs.so /bin/sh -c 'exit 0' || { echo "shim breaks binaries"; exit 1; }
echo "fixture ready: crate at /app/pennant ($(git -C "$CRATE" rev-parse --short HEAD)), reference at $REF, shim at /opt/libcountallocs.so"