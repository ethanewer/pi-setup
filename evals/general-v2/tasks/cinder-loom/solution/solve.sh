#!/bin/bash
# Cinder Loom oracle. Writes the deliverable recovery tool /app/carve.py, then
# RUNS it on the visible store to materialize /app/recovered. Never reads /tests.
set -eu

cat > /app/carve.py <<'PY'
#!/usr/bin/env python3
"""Loom flash-store carver: recover deleted, CRC-intact payloads into outdir."""
import os
import struct
import sys
import zlib


def main(argv):
    if len(argv) != 3:
        print("usage: carve.py <store_path> <outdir>", file=sys.stderr)
        return 2
    store_path, outdir = argv[1], argv[2]
    data = open(store_path, "rb").read()

    if data[:8] != b"LOOMSTR\x01":
        print("bad magic", file=sys.stderr)
        return 1
    (count,) = struct.unpack_from("<H", data, 8)

    # clean-dir semantics: the output directory must end up containing exactly
    # the recovered files, so purge any pre-existing artifacts first.
    os.makedirs(outdir, exist_ok=True)
    for name in os.listdir(outdir):
        p = os.path.join(outdir, name)
        if os.path.isfile(p) or os.path.islink(p):
            os.remove(p)
        else:
            import shutil
            shutil.rmtree(p)

    off = 10
    recovered = 0
    for _ in range(count):
        flags, name_len = struct.unpack_from("<BB", data, off)
        off += 2
        name = data[off:off + name_len].decode("ascii")
        off += name_len
        data_off, data_len, crc = struct.unpack_from("<III", data, off)
        off += 12
        if not (flags & 0x01):
            continue  # ACTIVE entry: not a recovery target
        blob = data[data_off:data_off + data_len]
        if len(blob) != data_len or zlib.crc32(blob) != crc:
            continue  # ROT / truncated payload: unrecoverable
        with open(os.path.join(outdir, name), "wb") as fh:
            fh.write(blob)
        print("RECOVERED %s" % name)
        recovered += 1
    print("TOTAL=%d" % recovered)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x /app/carve.py

python3 /app/carve.py /app/store.img /app/recovered

echo "solve.sh done -> /app/carve.py and /app/recovered"
ls -l /app/carve.py
ls -la /app/recovered
