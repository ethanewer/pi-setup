# lwrecord

Container codec for the **LW01** binary record format (version 1).  A
`Record` is a bundle of variable-length `Section` payloads behind one
little-endian header and a CRC-32 trailer.  The implementation currently
ships with stub bodies; implementing `crc32`, `encode` and `decode` in
`src/lib.rs` (or in modules you add) is the point of the exercise.

## Layout

```
src/lib.rs    public API: Record, Section, FormatError, crc32, encode, decode
tests/        integration tests (round-trip/property and error classification)
```

The crate has **zero external dependencies** on purpose: the trial container
has no network, so builds must resolve from the standard library alone.

## Wire format (version 1)

All multi-byte integers are unsigned little-endian.

```
header (19 bytes):
  [0..3]    magic          4C 57 30 31  ("LW01")
  [4]       version        u8, must be 1
  [5..6]    flags          u16, must be 0
  [7..10]   record id      u32
  [11..14]  section count  N, u32, 0 <= N <= 32
  [15..18]  payload length P, u32 (sum of all section payload lengths)
body (N sections, each):
  [0]       section kind   u8, 1..=255 (0 is reserved and rejected)
  [1..4]    payload length u32
  [5..]     payload bytes
trailer (4 bytes):
  CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320, init 0xFFFFFFFF,
  final bitwise complement) over every byte from offset 0 up to but not
  including the trailer.
```

Total encoded size is `23 + 5N + P` bytes.

## Decoding rules

`decode` is a total function: every input yields either `Ok(Record)` or a
`FormatError`, and it never panics.  When several defects coexist, the first
one in the table below wins:

| order | error | condition |
|------:|-------|-----------|
| 1 | `Truncated` | fewer than 19 bytes |
| 2 | `BadMagic` | bytes 0..3 are not "LW01" |
| 3 | `UnsupportedVersion` | version byte is not 1 |
| 4 | `BadFlags` | flags field is nonzero |
| 5 | `TooManySections` | N > 32 |
| 6 | `Truncated` | fewer than `23 + 5N` bytes in total |
| 7 | `Truncated` / `InvalidSectionType` | per section, in order: the section header or payload overruns the buffer (before the trailer), then the kind byte is 0 |
| 8 | `TrailingBytes` | bytes remain between the last section payload and the trailer |
| 9 | `PayloadMismatch` | header P differs from the sum of section payload lengths |
| 10 | `BadChecksum` | trailer does not match CRC-32 of the preceding bytes |

## Build and test

```
cargo test --offline
```

The suite comprises a fixed wire vector, generated round-trip and
perturbation properties, and one test per error variant plus precedence
pinning.  Do not modify the files under `tests/`.
