# Create a PPM image

Create a new **PPM** (Portable Pixmap) image file at `/app/img.ppm`.

It must be a valid **P3** (plain-text) PPM image with these exact header values:

- magic number: `P3`
- width: `6`
- height: `4`
- max color value: `255`

The pixel data (read row-major, top row first) must be:

- rows 0 and 1: solid **pure red** — every pixel RGB `255 0 0`
- rows 2 and 3: solid **pure blue** — every pixel RGB `0 0 255`

So the file is 24 pixels (4 rows × 6 columns) of triples. The verifier parses the header tokens and then reads all 24 `(r,g,b)` triples, checking each pixel against the pattern above. Exact spacing/whitespace does not matter; only the token sequence after the header.

Write the PPM text to `/app/img.ppm`.