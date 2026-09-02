# Recover live records from a damaged archive volume

A tape archive was damaged during migration. The on-disk volume image at
`/app/volume.bin` is intact except that some records were deleted (left as
tombstones) and a few payloads have been corrupted. Every slot is still
labelled, so the live records can be reconstructed by parsing the binary
container.

You must write a **reusable Python program** that recovers the live records
from **any** volume file following the format described below, then run it on
the supplied `/app/volume.bin` to produce the two required artifacts.

## Deliverables (all under `/app`)

1. `/app/recover.py` — a reusable script implementing the full recovery
   contract below. It must work on **any** volume file that conforms to the
   documented format, not just today's example.

   CLI contract (exactly three arguments):

   ```
   python3 /app/recover.py <volume_file> <out_recovered.json> <out_evidence.json>
   ```

   It reads the binary `<volume_file>`, writes the recovered records to
   `<out_recovered.json>` and the evidence log to `<out_evidence.json>`, and
   exits with status `0` on success. Write the JSON files using UTF-8. You may
   use only the Python standard library.

2. `/app/recovered.json` — produced by running your script on the given image:
   `python3 /app/recover.py /app/volume.bin /app/recovered.json /app/evidence.json`

3. `/app/evidence.json` — the corresponding evidence log (same command).

Do **not** modify `/app/volume.bin` or anything under `/tests`.

## Volume format (little-endian, 32-bit words)

Header — 16 bytes:

| offset | field            | meaning                              |
|--------|------------------|--------------------------------------|
| 0      | magic            | the 4 bytes `VOL1`                   |
| 4      | `page_size`      | u32 size of the data region          |
| 8      | `table_offset`   | u32 byte offset of the record table  |
| 12     | 4    | reserved         | u32, ignored                         |

Record table — starting at `table_offset`, a sequence of fixed **32-byte** slots
running to end of file:

| offset | size | field             | meaning                                          |
|--------|------|-------------------|--------------------------------------------------|
| 0      | 4    | magic             | u32 `0x52454331` (the bytes `b'REC1'`)           |
| 4      | 4    | `status`          | u32: `1` = live, `0` = tombstone                 |
| 8      | 4    | `payload_offset`  | u32 byte offset of this record's payload         |
| 12     | 4    | `payload_len`     | u32 length of the payload in bytes               |
| 16     | 4    | `crc32`           | u32 IEEE CRC-32 of the payload bytes             |
| 20     | 12   | reserved          | ignored                                          |

Each record's payload is a block of `payload_len` bytes stored at
`payload_offset` within the file.

## Recovery algorithm (exact)

1. Read the whole file. If the file is shorter than 16 bytes, **or** its first
   4 bytes are not `b'VOL1'`, the volume is *invalid*: emit
   `{"records": [], "status": "invalid"}` and continue (see Evidence).
2. Otherwise decode `page_size` and `table_offset`. A slot is **unscannable**
   (treated as absent) when the file ends within its 32 bytes. A slot is valid
   only if **all** of these hold:
   - its magic equals `0x52454331`,
   - its `status` equals `1` (live; status `0` = tombstone or unused slots are
     skipped),
   - `payload_len <= 4096`,
   - `payload_offset + payload_len <= page_size`, **and**
   - `payload_offset + payload_len <=` the file length,
   - the payload bytes decode cleanly as UTF-8,
   - the stored `crc32` equals the IEEE CRC-32 of the actual payload bytes.
   If any of those fail, the slot is skipped.
3. The recovered records are the valid live slots **in table order**, numbered
   `id = 1, 2, 3, ...` and reported as `{"id": N, "text": "<payload>"}` where
   `<payload>` is the payload decoded as UTF-8. Emit:

   ```json
   {"records": [{"id": 1, "text": "hello"}, ...], "status": "recovered"}
   ```

   `"status"` is `"recovered"` whenever the header was valid, whether or not any
   records were actually recovered.

## Evidence log

`<out_evidence.json>` must be:

```json
{
  "image_sha256": "<sha256 of the entire volume file, hex>",
  "records_sha256": "<sha256 over the concatenation of recovered payload bytes, in id order>"
}
```

- `image_sha256` is the hex SHA-256 of every byte of `<volume_file>`.
- `records_sha256` is the hex SHA-256 of the byte-by-byte concatenation of the
  recovered records' **payload bytes** in `id` order (empty hash for zero
  records). Because each recovered payload is valid UTF-8, this equals the
  SHA-256 of the UTF-8 bytes of the concatenated `"text"` fields.

## The program must generalize

The verifier runs your `recover.py` on several **hidden** volume files (fresh
scenarios, fresh records bytes) in addition to the visible case. It will probe,
among others:

- **Overlapping bookkeeping**: a valid header with an empty record table, and a
  table of nothing but tombstones.
- **Bad and missing records**: a slot whose stored CRC does not match its
  payload, and a slot pointing at an out-of-bounds payload.
- **Truncated / corrupt header**: a file whose magic is wrong, and a file
  shorter than 16 bytes.
- **Boundary addresses**: a live record whose `payload_offset + payload_len`
  runs exactly up to `page_size` (must be kept), an empty payload (length 0),
  and a `payload_len` greater than 4096 (must be skipped).
- **Unused land**: table slots that are zeroed or hold a non-`REC1` magic (must
  be skipped without error).

## Success criteria

`/app/recover.py` byte-correctly recovers `/app/volume.bin` into
`/app/recovered.json` and `/app/evidence.json`, and the same script also runs
correctly, without error, on the hidden volumes above. The verifier executes
your program — it does not just read a fixed answer. `/app/volume.bin` must
remain byte-for-byte unchanged.