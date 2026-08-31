#!/bin/bash
# Real oracle for tarn-mesa: write the extractor program, then RUN it on the
# shipped capture to produce /app/recovered.npy. Never reads /tests.
set -eu

EXTRACTOR="/app/extract.py"
OUT="/app/recovered.npy"

cat > "$EXTRACTOR" <<'PY'
#!/usr/bin/env python3
"""Extract the PRISM-1 matrix stored in a container file to a .npy file."""
import struct
import sys
import zlib

import numpy as np

MAGIC = b"PRSM"
FLAG_LITTLE = 0x01
FLAG_COLMAJOR = 0x02
FLAG_MASKED = 0x04


def extract(path):
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:4] != MAGIC:
        raise ValueError("bad magic")
    version = blob[4]
    if version != 1:
        raise ValueError("unsupported version %d" % version)
    flags = blob[5]
    mask_key = struct.unpack_from("<H", blob, 6)[0]
    nrows, ncols, header_len = struct.unpack_from("<IIH", blob, 8)
    if header_len < 18:
        raise ValueError("header_len too small")
    start = header_len
    n = 4 * nrows * ncols
    payload = bytearray(blob[start:start + n])
    if len(payload) != n:
        raise ValueError("truncated payload")
    if flags & FLAG_MASKED:
        kb = struct.pack("<H", mask_key)
        for i in range(n):
            payload[i] ^= kb[i % 2]
    dt = np.dtype("<f4") if flags & FLAG_LITTLE else np.dtype(">f4")
    flat = np.frombuffer(bytes(payload), dtype=dt)
    order = "F" if flags & FLAG_COLMAJOR else "C"
    return flat.reshape((nrows, ncols), order=order).astype("<f4")


def main():
    if len(sys.argv) != 3:
        print("usage: extract.py <container> <output_npy>", file=sys.stderr)
        return 2
    mat = extract(sys.argv[1])
    np.save(sys.argv[2], mat)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$EXTRACTOR"

python3 "$EXTRACTOR" /app/capture.prsm "$OUT"

echo "solve.sh done -> $EXTRACTOR and $OUT"
ls -l "$EXTRACTOR" "$OUT"
