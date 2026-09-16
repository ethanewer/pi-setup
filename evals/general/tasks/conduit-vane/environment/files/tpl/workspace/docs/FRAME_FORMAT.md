# Frame format

A veldt *capture* is an append-only sequence of frames. Every frame is
self-delimiting and carries its own integrity checksum, so a reader can start
at any frame boundary without state from earlier frames.

## Byte layout

```
off  size  field
0    1     MAGIC        fixed 0xA6
1    1     KIND         frame kind tag (below)
2    4     SEQ          sequence number, little-endian, starts at 0 per capture
6    8     TS_MS        capture-local timestamp in milliseconds, little-endian
14   4     PLEN         payload length in bytes, little-endian
18   PLEN  PAYLOAD      opaque payload
18+PLEN
     4     CRC32        ISO-HDLC checksum over the preceding 17+PLEN bytes
```

A minimal frame is therefore 22 bytes (zero-length payload).

## Kind tags

| tag | kind      | payload meaning                          |
|-----|-----------|------------------------------------------|
| 0x01| heartbeat | empty                                    |
| 0x02| status    | ASCII text (station state line)          |
| 0x03| sample    | u32 LE sample count, then count f64 LE   |
| 0x04| alarm     | ASCII text (alarm description)           |
| 0x05| manifest  | ASCII text (capture descriptor)          |
| 0x06| tail      | empty; the final frame of a capture      |

## Checksum

CRC-32/ISO-HDLC, the family `crc32_iso` in `veldt-core` implements: reflected
table, polynomial `0x04C11DB7`, initial register `0xFFFFFFFF`, final XOR
`0xFFFFFFFF`. The checksum covers the frame from the MAGIC byte through the
last payload byte; the four checksum bytes themselves are not covered.

## Sequence rules

- The first frame of a capture has sequence 0; each following frame is one
  greater.
- The frame reader in `veldt-transport` checks sequence continuity by default
  (`FrameReader::open`). A capture with a gap or a re-ordering is reported as
  an error, never silently misread.
- The `tail` frame is a normal, numbered frame; the *end of stream* is the
  condition "the source has no more bytes".

## Sizing

`PLEN` is capped at 1,048,576 bytes. Longer payloads are rejected at decode
time. Captures may be arbitrarily long; the transport layer reads them in
windows rather than loading them whole.

`veldt` writes captures from the `capture` subcommand with a deterministic
pseudo-random generator, so the same seed and frame count reproduce the same
file byte for byte. This is what the example capture and the fixture captures
rely on.