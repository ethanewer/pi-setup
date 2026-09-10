# conduit-vane: resume capability for the veldt field net

You are an engineer on the **veldt** field-telemetry project. Veldt runs a
mesh of unattended stations ("fobs") that record sensor traces and ship
captures to a collection service ("the well") over slow, intermittent,
power-hungry links. A fob that loses power must be able to continue where it
left off instead of re-reading a capture from the start.

You have been handed the Rust workspace at **`/app/workspace/`** — the
entire protocol and its tooling, with a git history, documentation, and a
passing test suite. Your job is to ship the **resume capability** that the
project's own integration contract calls for, in a way the downstream
station SDKs can build against.

## What is on disk

`/app/workspace/` is a Cargo workspace of four crates — `veldt-core`
(framing, codecs, checksums), `veldt-measure` (quantities and units),
`veldt-transport` (byte sources/sinks, frame reader/writer, sessions), and
`veldt-cli` (the `veldt` binary) — plus `docs/` and `example/`. Before you
touch anything, the workspace builds (`cargo build --workspace`), its test
suite is green (`cargo test --workspace`), and its git history tells the
story of how each crate grew. Read the docs first; they describe the
architecture, the frozen on-wire frame format, and — in
**`docs/ARCHITECTURE.md`** and **`docs/INTEGRATION.md`** — the one capability
the code does not yet provide and why it is needed.

## Environment

- Ubuntu 24.04 with `rustc`/`cargo` 1.75 (from the archive), `gcc`, `git`,
  and Python 3. Everything compiles **from the standard library only**; the
  container has **no network access**, so a change that adds a third-party
  dependency cannot resolve. Do not try to install anything.
- One CPU. `CARGO_BUILD_JOBS=1` is already set; do not raise it.
- The workspace repository is owned by root with a safe.directory exception;
  `git status`, `git log`, `git diff` and `git commit` all work from the
  container's user. Commit your change with clear message(s), as you would
  in production — but note that only the working tree is graded.
- You may only modify files inside `/app/workspace/`. Never modify anything
  under `/tests` or `/solution` (they are not even visible to you), and
  leave every other `/app` path alone.

## The outcome required

A downstream station firmware SDK — code that is **not in this container** —
must be able to do all of the following against `/app/workspace/`'s public
API once you are done:

1. open a capture, read and acknowledge some frames, and persist a compact
   **checkpoint** blob to durable storage;
2. load that blob later — after a power loss — and resume the capture
   exactly where the fob left off, without re-reading the acknowledged
   prefix;
3. detect, with a typed error and never a panic, a corrupt checkpoint, a
   capture whose acknowledged prefix changed, a capture shorter than the
   checkpoint, or a capture that ends in the middle of a frame.

The contract that defines the required public API surface, the semantics,
and the acceptance behavior lives in the repository itself. Read
`docs/INTEGRATION.md` in full and implement what it requires. The contract —
not this instruction — is the specification you are graded against.

### Hard requirements (all verified)

- `cargo build --workspace` exits 0.
- `cargo test --workspace` exits 0 (the shipped suite must stay green; do
  not delete, rename, or weaken existing tests).
- **No `unsafe` anywhere.** The verifier scans every `.rs`, `.toml`, `.md`
  and `.txt` file in `/app/workspace/` (excluding `target/` and `.git/`)
  and fails on the token. The capability must be implementable in safe Rust.
- **Semver for downstream consumers.** The public API of all four crates —
  names, signatures, and behaviors — must remain source- and
  behavior-compatible with what is shipped. Hidden downstream crates compile
  against the pre-change API and assert the behaviors they rely on
  (checksums, conversions, frame reading, strict sequence checks). A
  breaking change stops the whole release.
- The on-wire frame format is frozen (`docs/FRAME_FORMAT.md`). The example
  capture, and the hidden fixture captures, are in that format; consumers
  read them with *your* code.

### What is left to you

The internal design is deliberately unspecified here: where the new code
lives inside the crates, the blob layout, the integrity-digest algorithm,
the buffering strategy, and how the new reader composes with the existing
transport code. The contract pins the surface and the behavior — the 
implementation is your judgment call. The way to judge whether the design is
good is the same way anyone would: does it satisfy the contract's promises
under the abuse the contract describes?

## Working approach (suggested)

There is no single file to change and no bug to find. Start by reading the
repository: `README.md`, the four docs, then the crate sources and `git log
--oneline` to see how the pieces were built and where the seams are. Use the
shipped tooling to build mental models:

```
target/debug/veldt capture /tmp/probe.bin --seed 3 --frames 12 --samples 8
target/debug/veldt cat /tmp/probe.bin
target/debug/veldt replay /tmp/probe.bin
target/debug/veldt summarize example/capture.bin
target/debug/veldt units 1 hour second
```

Because the workspace has no external dependencies, `cargo build` and
`cargo test` are fast and offline; iterate with them. When you believe the
capability behaves per the contract, run the full workspace build and test
one final time, make sure the `unsafe` scan is clean, and commit your work
to the workspace git history.

## Grading

The verifier rebuilds the workspace, re-runs the whole test suite, scans
for `unsafe`, then takes copies of your crates and compiles and runs
downstream consumer crates against them: a semver sentinel that uses the
pre-change public API, and two consumers that use the new resume capability
against hidden fixture captures (different seeds, sizes, frame mixes). All
of it must pass; reward is binary.