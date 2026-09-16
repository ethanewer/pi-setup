# Architecture

Veldt is a four-crate Cargo workspace. Dependencies between crates point one
way: `core <- measure <- transport <- cli` plus `core <- transport`. Everything
is built from the standard library; there are no third-party dependencies and
no build-time network access.

```
                +----------------------+
                |  veldt-cli (binary)  |
                +----------+-----------+
                           |
             +-------------+-------------+
             |             |             |
   +---------v--+  +-------v-----+  +----v-------+
   | veldt-measure |  | veldt-transport |  | (cli-local) |
   +---------+-----+  +-------+---------+  +--------------+
             |                 |
             +--------+--------+
                      v
              +-----------------+
              |   veldt-core    |
              +-----------------+
```

## veldt-core

Everything below the frame boundary: growable byte buffers and cursor-style
readers (`bytes`), LEB128-style variable integers (`varint`), CRC-16/XMODEM
and CRC-32/ISO-HDLC checksums (`crc`), the frame kind taxonomy (`kinds`), the
frame codec itself (`frame`), and the shared error type (`error`). Crates above
core return `Result<T>` typed with `veldt_core::Error`, so callers can tell a
truncated stream from a bad checksum from a programming error without
downcasting.

## veldt-measure

Dimensioned quantities and their formatting. `unit` defines the unit taxonomy
and conversion factors to base SI, `prefix` the SI prefixes, `quantity` the
`Quantity` type with dimensional conversion, `interval` the `Interval` range
type, `series` a fixed-capacity numeric series with descriptive statistics,
and `format` the human-readable formatter and unit parser. This crate has no
knowledge of frames or streams; the CLI uses it to render sample payloads in
meaningful units.

## veldt-transport

Streams and frames. `source` defines the `Src` trait (positional reads over a
durable byte source: memory, file, or a chain of parts) and `sink` the `Sink`
trait (append-only byte destinations). `reader` turns a `Src` into a strict
sequence-checking `FrameReader`; `writer` turns a `Sink` into a `FrameWriter`
that appends correctly checksummed frames; `session` tracks which sequences
have been seen, which is the acknowledgement state a fob uploads to the well.

The reading model matters: a `FrameReader` never holds more than one frame in
memory, keeps a cursor (`pos`) of how many bytes it has consumed, and derives
everything from the self-delimiting frame headers. Nothing in this crate
assumes the whole capture fits in RAM.

## veldt-cli

The `veldt` binary. Subcommands map one-to-one onto the crates:

| command   | purpose                                            |
|-----------|-----------------------------------------------------|
| `capture` | synthesize a deterministic capture (uses all three)  |
| `cat`     | dump frames                                         |
| `replay`  | read a capture with strict checks, print acks       |
| `summarize`| descriptive statistics of sample payloads          |
| `units`   | convert a quantity between units                    |
| `hash`    | print the ISO-HDLC checksum of a file               |

## Data flow

A fob writes one capture per mission. The `capture` tool (or the fob's own
writer) appends frames with strictly increasing sequences. When a link is up,
the fob ships the capture to the well; the well's reader verifies each frame's
checksum and sequence and records how far it got. The fob must not re-send
bytes the well has acknowledged, and on power loss it must be able to resume
from the *last acknowledged* position rather than from the start of the file.

That resume path is the subject of `docs/INTEGRATION.md`.