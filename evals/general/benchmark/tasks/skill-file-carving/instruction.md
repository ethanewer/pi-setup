# File carving: recover an embedded PNG

`/app/blob.bin` is a raw byte buffer that contains a complete embedded PNG image
interleaved with unrelated "junk" bytes before and after it. Your job is to
carve out the PNG.

A PNG file always starts with the 8-byte signature `89 50 4E 47 0D 0A 1A 0A`
(bytes for `\x89PNG\r\n\x1a\n`) and always ends with an `IEND` chunk. The `IEND`
chunk is laid out as: a 4-byte length field `\x00\x00\x00\x00`, the 4 ASCII
bytes `49 45 4E 44` (`IEND`), then a 4-byte CRC. If `p` is the byte offset where
the ASCII bytes `IEND` begin, the chunk occupies `[p-4, p+8)`, so the PNG file
ends at `p + 8`.

## Your task

Write a Python 3 script `/app/carve.py` that:

1. reads `/app/blob.bin`,
2. finds the offset of the PNG signature,
3. finds the ASCII `IEND` sequence, and carves the exact byte range
   `[signature_offset, iend_offset + 8)`,
4. writes:
   - `/app/carved.png` — the carved bytes (the recovered PNG file),
   - `/app/carved.json`:
     ```json
     {"offset": <int byte offset where the signature starts>,
      "length": <int number of carved bytes>,
      "valid_ending": true}
     ```

Run the script so both files exist. The verifier independently locates the PNG
in `/app/blob.bin` and checks that `/app/carved.png` is byte-for-byte identical
to the embedded PNG and that the JSON fields are correct.