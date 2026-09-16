# lintel-winch — implement the LW01 record container codec in Rust

You are a systems programmer joining the telemetry-archive team at **Lintel
Instrument Works**. Field devices send hourly bundles in a fixed binary record
container format ("LW01", version 1). The crate in `/app/lwrecord/` is a
clean-room cargo project that will ship in the team's ingest pipeline. Its
library root module currently exposes the crate's public API with **stubbed
function bodies**, and the integration test suite under `tests/` is failing.

Your job: **implement the codec** so that the shipped test suite passes and
`cargo test` reports green. This is a systems programming task in Rust 1.75.

## Environment

- `rustc`/`cargo` 1.75 are installed on PATH.
- The crate is at `/app/lwrecord/` (this is your only deliverable).
- The container is **offline at trial time**. The crate has **zero external
  dependencies** and must keep it that way: builds must resolve from the
  standard library alone, and `cargo test` must work with no network.
- `README.md` inside the crate documents the crate, the exact wire format,
  the decode error table, and the error precedence. The same contract is
  repeated below; when in doubt the rule here governs.

## The LW01 wire format (version 1)

All multi-byte integers are **unsigned little-endian**. A record is:

```
header (19 bytes):
  [0..3]    magic          4C 57 30 31  ("LW01")
  [4]       version        u8, must be 1
  [5..6]    flags          u16, must be 0
  [7..10]   record id      u32
  [11..14]  section count  N, u32, 0 <= N <= 32
  [15..18]  payload length P, u32, must equal the sum of all section
            payload lengths
body (N sections, each):
  [0]       section kind   u8, 1..=255 (0 is reserved and rejected)
  [1..4]    payload length u32
  [5..]     payload bytes
trailer (4 bytes):
  CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320, init 0xFFFFFFFF,
  final bitwise complement) over every byte from offset 0 up to but not
  including the trailer.
```

Total encoded size is `23 + 5N + P` bytes. The empty record (N=0, P=0) is
exactly 23 bytes.

## Public API (fixed contract)

The public items declared in the crate's library root module — the `Record`
and `Section` structs with their public fields, the `FormatError` enum, and
the functions `crc32`, `encode`, `decode` — must keep their exact names,
signatures and meanings. The verifier compiles **additional** test files
against this API after you finish. `encode` must produce byte-for-byte
canonical output (no padding, no alternate encodings) and `crc32` must
implement the polynomial above.

### `decode` error semantics

`decode` is a **total function**: every input, including arbitrary garbage,
must yield either `Ok(Record)` or a `FormatError` — never a panic, never an
infinite loop. Check every bound. When several defects coexist in one input,
report the **first** one in this table:

| order | error | condition |
|------:|-------|-----------|
| 1 | `Truncated` | fewer than 19 bytes |
| 2 | `BadMagic` | bytes 0..3 are not "LW01" |
| 3 | `UnsupportedVersion` | version byte is not 1 |
| 4 | `BadFlags` | flags field is nonzero |
| 5 | `TooManySections` | N > 32 |
| 6 | `Truncated` | fewer than `23 + 5N` bytes in total |
| 7 | `Truncated`, then `InvalidSectionType` | per section, in order: the section header or its payload overruns the buffer (before the trailer); the kind byte is 0 |
| 8 | `TrailingBytes` | bytes remain between the last section payload and the trailer |
| 9 | `PayloadMismatch` | header P differs from the sum of section payload lengths |
| 10 | `BadChecksum` | trailer does not match CRC-32 of the preceding bytes |

## Requirements

1. **Don't touch** anything under `tests/` or `README.md`. The shipped tests
   lock the wire layout, the CRC-32 check values, the round-trip property and
   each error variant. The verifier checks that the shipped tests are still
   present and still all pass.
2. **No `unsafe`**: the delivered crate must not contain the keyword `unsafe`
   anywhere in its source, tests, `Cargo.toml` or `README.md`. The verifier
   greps the crate for it.
3. The crate must remain zero-dependency and buildable offline.
4. When you are done, `/app/lwrecord/` must satisfy:
   - `cargo test --offline` exits 0 with the full shipped suite green
     (no skipped or ignored tests);
   - the same command stays green when the verifier drops fresh hidden test
     files into the crate's `tests/` directory — so keep the documented
     public API and the documented error variants exact.

## Internal design is yours

You may implement everything in the root library module, split the crate into
additional modules under `src/`, add private helpers, or restructure the
internals freely. Keep the documented public API unchanged. There is no
single correct layout; the verifier only re-runs the tests.

## Deliverable

- `/app/lwrecord/` — the completed crate (its own `Cargo.toml`, the library
  implementation, and the unmodified shipped tests). Nothing else is graded.
