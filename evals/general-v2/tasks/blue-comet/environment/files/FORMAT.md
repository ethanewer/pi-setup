# Blue Comet block format

A *stream* is a concatenation of independent *blocks*. Each block is:

```
offset  size  field
0       4     magic string  "BC7!"  (bytes 0x42 0x43 0x37 0x21)
4       2     planned_len  uint16, big-endian   (0 .. 65535 bytes)
6       1     block_type:  0x00 literal | 0x01 RLE
7       ...   payload
```

### literal block (type 0x00)
`planned_len` raw bytes follow verbatim.

### RLE block (type 0x01)
The payload is a sequence of run pairs `(run_len u8, byte u8)`.
- The sum of all `run_len` values in the block must equal `planned_len` exactly.
- Each `run_len` must be in 1..255 (0 is invalid).
- A run must never push the cumulative decoded count beyond `planned_len`.

### exact positioning
decode consumes precisely the bytes of each block, so a stream is just the
blocks laid end to end with no padding. There is no global total-length field;
each block carries its own `planned_len`.

## Invalid / malformed streams (decode MUST raise, no output)
1. Fewer than 7 bytes remain to form a block header (truncated header/magic).
2. The 4-byte magic does not equal `BC7!`.
3. `block_type` is neither 0x00 nor 0x01.
4. literal block whose payload has fewer than `planned_len` bytes.
5. RLE block where the byte stream ends before the run pairs fill `planned_len`
   (truncated/underfilled).
6. RLE block where a run would push the count beyond `planned_len`.
7. RLE block containing a `run_len` of 0.

## Edge cases that are VALID
- An empty stream (zero blocks) decodes to zero bytes.
- A block with `planned_len == 0` and type 0x00 is a valid empty literal block.
- `planned_len` up to 65535; input longer than 65535 bytes must be split into
  multiple blocks by the encoder.
- A run may be up to 255 bytes.