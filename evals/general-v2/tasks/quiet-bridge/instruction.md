# QuietBridge telemetry decoder

You are writing a small command-line tool that decodes a self-describing binary
"quiet bridge" telemetry stream from a hex-encoded text file.

## Deliverable

Write the program **`/app/decode.py`**. It must be a general tool that works on
**any** input file satisfying the contract below — not just the sample you see.
Do not modify any input file. Do not read `/tests`.

## Interface

```
python3 /app/decode.py <input.hex> <output.json>
```

- `<input.hex>`: text file containing the hexadecimal (lower- or upper-case)
  bytes of a binary stream. Whitespace (spaces, tabs, newlines) anywhere in the
  file is ignored. If the file contains no parseable bytes, treat it as an empty
  stream.
- `<output.json>`: path to write the result JSON. The tool creates this file.
- Exit code 0 on success.

## Byte stream format

The stream is a sequence of frames, possibly with garbage bytes between or
around them. Each frame, once located, has this layout:

```
 0       1       2       3       4       5       6       7 .. 7+N   7+N
+-------+-------+-------+-------+-------+-------+-------+-------------+-----+
| 'Q'(0x51) | 'B'(0x42) | 'X'(0x58) | '7'(0x37) | len_lo | len_hi | seq | N payload bytes | cksum |
+-------+-------+-------+-------+-------+-------+-------+-------------+-----+
```

- Magic: the 4 bytes `0x51 0x42 0x58 0x37` (ASCII `QBX7`).
- Payload length: a little-endian `uint16` (byte 4 = low, byte 5 = high).
- Sequence: 1 byte holding the frame's sequence number (0..255).
- Payload: exactly `N` bytes following the sequence byte.
- Checksum: 1 byte = `(sum of the 7 header bytes + sum of the N payload bytes) mod 256`.
  For a frame this is the sum of bytes 0..6 plus every payload byte.

A frame is **accepted** only if all of the following hold:

1. It begins with the magic marker `QBX7` at the scan position.
2. The stream contains enough bytes for the full frame (i.e. it does not run out
   before the declared payload length and the checksum byte).
3. The stored checksum byte equals the computed `sum(...) mod 256` described
   above.

If any condition fails, the frame is **discarded** (counted) and scanning resumes
from the byte **after** the magic marker that began that attempt, looking for the
next magic marker. Bytes that never form a magic marker are simply skipped and
are **not** counted as discarded. Once a frame is accepted, scanning continues at
the byte after its checksum.

## Output

Write JSON with exactly this structure:

```json
{
  "discarded": 0,
  "records": [
    { "seq": 1, "text": "xy" },
    { "seq": 2, "text": "abc" }
  ]
}
```

- `discarded`: integer count of frames that began with a magic marker but were
  rejected (bad checksum, truncated declaration, etc.). Not counting pure garbage.
- `records`: one object per **accepted** frame, with `seq` (int) and `text`
  (the payload decoded as UTF-8). The records array must be sorted
  **ascending by sequence number** (stable — equal sequence numbers keep their
  stream arrival order). This reordering is intentional: inbound frames may
  arrive out of sequence.

Field names are exactly `discarded`, `records`, `seq`, `text`.

## Edge cases the verifier will probe

Write your decoder to handle **all** of these:

- Valid frames arriving out of sequence → output must still be sorted ascending
  by `seq`.
- A frame whose checksum byte does not match → discarded.
- A frame that is truncated: the declared payload length exceeds the bytes that
  remain, or the checksum byte is missing → discarded.
- A declared payload length inconsistent with the actual byte count present.
- Zero-length payloads (valid; `text` is `""`).
- Garbage bytes before, between, or after frames (not counting magic) → ignored,
  not discarded.
- A hex file containing whitespace of any sort (spaces, tabs, newlines, leading
  blank lines), upper- or lower-case hex digits.
- Duplicate sequence values (still handled by the stable ascending sort).
- An input with no valid frames at all → `{"discarded": 0, "records": []}`.

The sample data in `/app/stream.hex` is a normal case with two valid frames and
zero discarded frames. Your program must also pass additional hidden cases built
on the same documented contract.

## Success

Your task is finished when `/app/decode.py` exists, is executable by `python3`,
parses any conforming input, and produces the JSON described above. The
evaluation runs `/app/decode.py` on the sample input and several hidden inputs.