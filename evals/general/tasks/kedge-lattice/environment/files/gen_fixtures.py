#!/usr/bin/env python3
"""Deterministic PNG fixture generator for the kedge-lattice task (authoring
provenance only; this script is not run at trial time).

Every fixture is an 8-bit RGBA PNG built from pure arithmetic and a seeded
PRNG -- no time, no os.urandom -- so the same bytes are produced on any
machine. The committed fixtures under fixtures/ and tests/hidden/*/ were
generated with:

    python3 gen_fixtures.py <outdir>
"""
import random
import struct
import sys
import zlib


def png_bytes(w, h, px):
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *p) for p in row) for row in px
    )

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def make(outdir, name, w, h, seed):
    rnd = random.Random(seed)
    px = []
    for y in range(h):
        row = []
        for x in range(w):
            if name.startswith("vis1"):
                r = 255 * x // (w - 1) if w > 1 else 0
                g = 255 * y // (h - 1) if h > 1 else 0
                b = 255 if ((x // 4 + y // 4) % 2) else 0
                a = 255 * (x + y) // (w + h - 2) if (w + h) > 2 else 255
            elif name.startswith("vis2"):
                r = 200 if (x // 3) % 2 else 40
                g = 210 if (y // 5) % 2 else 30
                b = 90
                d = (x - w / 2) ** 2 + (y - h / 2) ** 2
                a = 255 if d < (min(w, h) / 2) ** 2 else 128
            else:  # hidden fixtures: deterministic modular pattern
                r = (x * 37 + y * 13) % 256
                g = (x * 91 + y * 29) % 256
                b = (x * 47 + y * 71) % 256
                a = 255 if ((x * 7 + y * 11) % 3) else 0
            row.append((r & 255, g & 255, b & 255, a & 255))
        px.append(row)
    with open(f"{outdir}/{name}.png", "wb") as fh:
        fh.write(png_bytes(w, h, px))
    print(f"{name}.png {w}x{h} written")


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    make(outdir, "vis1", 40, 30, 1)
    make(outdir, "vis2", 32, 44, 2)
    make(outdir, "case1", 64, 40, 11)
    make(outdir, "case2", 36, 36, 12)
    make(outdir, "case3", 50, 34, 13)