# Veldt — field telemetry capture, framing, and transport

Veldt is a small telemetry stack for a mesh of unattended field stations.
Each station (a "fob") records sensor traces to append-only capture files,
then ships those files to a central collection service (the "well") whenever
a data link is available. Links are slow, lossy, and intermittent, so the
codebase cares about one thing above all else: **never re-reading bytes that
an upstream system has already acknowledged.**

This repository is the Rust implementation of the protocol and its tooling.
It is one Cargo workspace with four crates:

| crate            | role                                                        |
|------------------|-------------------------------------------------------------|
| `veldt-core`     | byte buffers, varints, checksums, frame types and framing   |
| `veldt-measure`  | dimensioned quantities, SI prefixes, intervals, series      |
| `veldt-transport`| byte sources/sinks, frame reader/writer, session tracking   |
| `veldt-cli`      | the `veldt` command line tool (capture / cat / replay / ...)|

## Layout

```
crates/
  veldt-core/        framing and codec primitives, no upstream deps
  veldt-measure/     quantities and units, depends on veldt-core
  veldt-transport/   stream abstractions over frames, depends on veldt-core
  veldt-cli/         the command line binary, depends on all three
docs/
  ARCHITECTURE.md    crate boundaries and data flow
  FRAME_FORMAT.md    the on-wire frame layout
  INTEGRATION.md     contracts for downstream consumers
  OPS_RUNBOOK.md     operations notes for running fobs and wells
example/
  capture.bin        a small demo capture produced by `veldt capture`
  stations/          editable station manifests
```

## Building and testing

```
cargo build --workspace
cargo test  --workspace
```

The workspace has no external dependencies: everything compiles from the
standard library, so a plain `cargo build` works offline.

## Quick tour

```
# synthesize a demo capture (deterministic for a given seed)
target/debug/veldt capture example/capture.bin --seed 11 --frames 40 --samples 24

# dump the frames of a capture
target/debug/veldt cat example/capture.bin

# verify every frame (magic, checksum, sequence) and print acks
target/debug/veldt replay example/capture.bin

# describe the samples in a capture
target/debug/veldt summarize example/capture.bin

# convert a quantity between units
target/debug/veldt units 1 hour second
```

The frame reader in `veldt-transport` treats a capture as an immutable,
append-only byte stream. Its sequence checks are strict by default, so a
capture that is truncated or re-ordered is reported loudly rather than
silently tolerated.

## History

This workspace was assembled from the field-net's standalone prototype
crates. `git log` tells the story: the core codecs landed first, then the
measure crate, then the transport layer, then the CLI, and finally the
integration documentation. The integration contract (`docs/INTEGRATION.md`)
describes one capability that the current code does **not** yet provide;
downstream consumers (station firmware SDKs) are expected to compile and run
against the workspace's public API once it does.