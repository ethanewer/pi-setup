# pennant

Binary framing for the **Pennant Frame Protocol**: tag- and length-prefixed
byte records (`MAGIC TAG LEN PAYLOAD`, see `docs/protocol.md`).

This repository is the reference implementation. It is a small, dependency-free
Rust library plus a tiny CLI (`pennpack`) and an integration test-suite that
locks the wire format byte-for-byte.

## Layout

    src/lib.rs         public API (stable, source-compatible)
    src/varint.rs      unsigned base-128 varint codec
    src/codec.rs       frame encoder
    src/decode.rs      frame decoder (allocation-free)
    src/bin/pennpack.rs  small command-line consumer of the API
    tests/             wire-format and round-trip integration tests
    docs/protocol.md   the wire format specification

## Building

    cargo test         # must stay green
    cargo build --release

## Performance status

The encoder (`encode_frame`) is a straight-forward v0.1 implementation: its
hot path performs heap allocations on every call (it builds the frame header
in scratch buffers). The public API and the wire format are fixed; only the
way encode produces bytes is allowed to change.
