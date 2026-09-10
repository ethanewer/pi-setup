# Pennant Frame Protocol

A Pennant frame is a tag- and length-prefixed binary record:

    MAGIC TAG LEN PAYLOAD

- **MAGIC** — the single byte `0xA7`. Every frame starts with it.
- **TAG** — a `u64` application tag, encoded as an unsigned base-128 varint.
- **LEN** — a `u64` payload length, encoded like TAG. It is the number of
  payload bytes that follow.
- **PAYLOAD** — exactly LEN raw bytes.

## Varint encoding

Unsigned base-128 (LEB128-style). The value is encoded low-to-high in groups
of 7 bits. The high bit of each group is the continuation flag: `1` on every
group except the final one. `u64` values therefore need at most 10 bytes.

| value     | varint bytes      |
|-----------|-------------------|
| 0         | `00`              |
| 127       | `7F`              |
| 128       | `80 01`           |
| 16383     | `FF 7F`           |
| 16384     | `80 80 01`        |
| 300       | `AC 02`           |
| u64::MAX  | ten bytes: nine `FF` then `01` |

## Examples

    frame(5, "")       ->  A7 05 00
    frame(0, "")       ->  A7 00 00
    frame(300, "XY")   ->  A7 AC 02 02 58 59

## Decoding rules

- Empty input, or input whose first byte is not `0xA7`: **BadMagic**.
- Header incomplete, or LEN exceeds the bytes that remain: **Truncated**.
- More than 10 varint groups for a value: malformed (**Truncated**).
- `decode_frame` treats the buffer as exactly one frame: trailing bytes are
  an error. `decode_first` returns the frame plus the number of bytes it
  occupies, so a stream of frames can be scanned.

Implementations must not change the wire format. The public API is stable.
