# Create a valid PNG image

Create a brand-new **PNG image file** at `/app/solid.png`.

The required properties of the file:

- It is a valid, non-interlaced **PNG** image (8-bit truecolor, no alpha channel; PNG color type 2).
- Dimensions are exactly **4 pixels wide × 4 pixels high**.
- Every pixel is **opaque red**: R=255, G=0, B=0.
- It is a valid PNG that a decoder can read: the 8-byte PNG signature, an `IHDR` chunk carrying the width/height/bit depth/color type, `IDAT` chunk(s) holding the zlib-compressed raw scanlines, and a final `IEND` chunk — each with a correct CRC-32.

Concretely, the PNG bitstream is built as follows:

- Signature (8 bytes): hex `89 50 4E 47 0D 0A 1A 0A`.
- Each chunk is: `length(4 bytes big-endian)` + `type(4 ASCII bytes)` + `payload` + `CRC-32(4 bytes big-endian)`.
- `IHDR` (13-byte payload): width=4, height=4 (4-byte big-endian each), bit depth=8, color type=2 (truecolor), compression method=0, filter method=0, interlace method=0.
- Scanlines: each of the 4 image rows begins with one filter byte (`0` = None), followed by 12 bytes of RGB (4 pixels × 3 bytes). Decompressed size = 4 × 13 = 52 bytes.
- Compress those 52 bytes with zlib (for example `zlib.compress(data, 9)`) into an `IDAT` chunk.
- Terminate with an empty `IEND` chunk.

Python's standard library `zlib` and `struct` are available; no image library is required or assumed. Compute each chunk CRC with `zlib.crc32(type_bytes + payload)`.

Write the resulting bytes to `/app/solid.png`. The verifier opens it, walks the chunk stream, decompresses the scanlines, and verifies the header fields and that all 16 pixels decode to pure red.