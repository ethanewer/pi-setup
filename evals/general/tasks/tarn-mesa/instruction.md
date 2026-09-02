# Recover the matrix from a PRISM-1 instrument capture

A field instrument writes its sensor frames as **PRISM-1 container** binary
files. One capture, `/app/capture.prsm`, has been shipped to you. Your job is
to reverse-engineer the container **per the exact specification below**, write
a reusable extractor program, and use it to recover the matrix stored in the
capture as a NumPy `.npy` file.

Work in `/app`. **Do not modify or delete `/app/capture.prsm`.** Standard
library plus `numpy` are available; no network access.

## PRISM-1 container format (authoritative)

All multi-byte integers in the header and trailer are **little-endian**.

```
offset  size  field
0       4     magic, exactly the ASCII bytes "PRSM"
4       1     version byte, currently 0x01
5       1     flags bitmask:
                bit0 (0x01) payload floats are LITTLE-endian float32;
                            if clear they are BIG-endian float32
                bit1 (0x02) payload is stored COLUMN-major (Fortran order);
                            if clear it is ROW-major (C order)
                bit2 (0x04) payload bytes are XOR-masked with the 2-byte key
                            (see below); if clear the payload is stored as-is
6       2     mask_key (uint16); meaningful only when bit2 is set
8       4     nrows (uint32)
12      4     ncols (uint32)
16      2     header_len (uint16): total size of the header in bytes
18      ...   opaque padding bytes; these are junk and must be skipped.
              The payload starts exactly at byte offset header_len.
```

- The **payload** is exactly `4 * nrows * ncols` bytes of float32 sample data,
  starting at `header_len`.
- If bit2 is set, the payload was XOR-masked: byte `i` of the stored payload is
  `data[i] XOR mask_key_bytes[i mod 2]`, where `mask_key_bytes` is the 2-byte
  little-endian encoding of `mask_key`. Unmask before decoding the floats.
- After the payload comes a **4-byte trailer**: a CRC32 (zlib polynomial, uint32
  little-endian) of the payload bytes *as stored* (i.e. still masked). You do
  not have to verify it, but you must not treat it as sample data: read exactly
  `4*nrows*ncols` payload bytes, never to end-of-file.
- Decode the payload with the endianness selected by bit0, then reshape to the
  `(nrows, ncols)` matrix using row-major or column-major order as selected by
  bit1. The resulting matrix has dtype float32.

## Deliverables (both required)

1. `/app/extract.py` — a runnable Python program with this interface:
   ```
   python3 /app/extract.py <container> <output_npy>
   ```
   It parses any PRISM-1 container that follows the specification above and
   writes the recovered `(nrows, ncols)` float32 matrix to `<output_npy>` using
   `numpy.save`. It must work on **any** conforming container — different
   dimensions, either endianness, either memory order, mask present or absent,
   with or without header padding — not just on the shipped capture.

2. `/app/recovered.npy` — the matrix your program recovers **from the shipped
   `/app/capture.prsm`**:
   ```
   python3 /app/extract.py /app/capture.prsm /app/recovered.npy
   ```

## Correctness requirements probed by the grader

The verifier runs `/app/extract.py` unchanged on hidden containers that follow
the same format, so the extraction logic must be fully general. In particular
the grader probes:

- big-endian payloads (bit0 clear) as well as little-endian ones;
- column-major storage (bit1 set) as well as row-major;
- XOR-masked payloads (bit2 set) as well as unmasked ones;
- non-zero header padding (payload does not start at byte 18);
- the exact matrix **orientation**: a `(nrows, ncols)` array, not its
  transpose;
- correct dtype float32.

## Constraints

- Do not hard-code the shipped capture's bytes, dimensions, or flags.
- Do not modify `/app/capture.prsm`.
- No network access; `python3` + `numpy` only.
