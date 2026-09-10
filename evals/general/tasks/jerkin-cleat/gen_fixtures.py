#!/usr/bin/env python3
"""Generate image fixtures for the jerkin-cleat task (authoring-time tool).

Stdlib only. Produces:
  environment/files/fixtures/   (visible sample set the agent starts with)
  tests/hidden/case1|2|3/       (hidden generalization cases)

Deterministic: content is a pure function of (name, w, h, seed) so the same
bytes are produced on every run. PNGs use real zlib deflate so decoding them is
a real inflate, not a passthrough.
"""
import os
import struct
import zlib
import math

ROOT = os.path.dirname(os.path.abspath(__file__))
VIS = os.path.join(ROOT, "environment", "files", "fixtures")
HIDDEN = os.path.join(ROOT, "tests", "hidden")


def png_chunk(typ: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))


def write_png(path: str, w: int, h: int, bit_depth: int, color_type: int,
              rows, palette: bytes | None = None, trns: bytes | None = None):
    raw = b"".join(b"\x00" + r for r in rows)  # filter 0 per scanline
    ihdr = struct.pack(">IIBBBBB", w, h, bit_depth, color_type, 0, 0, 0)
    out = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr)
    if palette is not None:
        out += png_chunk(b"PLTE", palette)
    if trns is not None:
        out += png_chunk(b"tRNS", trns)
    out += png_chunk(b"IDAT", zlib.compress(raw, 9))
    out += png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def write_bmp24(path: str, w: int, h: int, rgba):
    row_size = (w * 3 + 3) & ~3
    data = b""
    for r in range(h - 1, -1, -1):  # bottom-up rows, BGR, padded
        row = b"".join(bytes((rgba[(r, c)][2], rgba[(r, c)][1], rgba[(r, c)][0]))
                       for c in range(w))
        data += row + b"\x00" * (row_size - w * 3)
    hdr = struct.pack("<2sIHHI", b"BM", 54 + len(data), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(data), 2835, 2835, 0, 0)
    with open(path, "wb") as f:
        f.write(hdr + info + data)


def write_tga24(path: str, w: int, h: int, rgba):
    # TGA 2.0 truecolor, uncompressed, top-left origin (descriptor 0x20)
    hdr = (bytes([0, 0, 2])                       # id_len, cmap_type, image_type
           + struct.pack("<HHB", 0, 0, 0)        # cmap origin, length, depth
           + struct.pack("<HHHHBB", 0, 0, w, h, 24, 0x20))  # origin x/y, w, h, bits, descr
    data = b"".join(bytes((rgba[(r, c)][2], rgba[(r, c)][1], rgba[(r, c)][0]))
                    for r in range(h) for c in range(w))
    with open(path, "wb") as f:
        f.write(hdr + data)


# ---------------------------------------------------------------------------
# content: deterministic patterns -> RGBA rasters
# ---------------------------------------------------------------------------
def pattern(w: int, h: int, seed: int):
    """Return {(r,c): (r,g,b,a)} with varied structure."""
    out = {}
    s = seed * 9301 + 49297
    for r in range(h):
        for c in range(w):
            s = (s * 1103515245 + 12345) & 0x7FFFFFFF
            jitter = (s % 200) / 100.0 - 1.0
            u = c / max(1, w - 1)
            v = r / max(1, h - 1)
            x = c - w / 2.0
            y = r - h / 2.0
            rad = math.sqrt(x * x + y * y) / max(w, h)
            if seed % 2 == 0:
                rv = int(255 * (0.5 + 0.5 * math.sin(3.0 * u + jitter * 0.5)))
                gv = int(255 * (0.5 + 0.5 * math.sin(3.0 * v + 2.1 + jitter * 0.4)))
                bv = int(255 * (0.5 + 0.5 * math.sin(2.2 * (u + v) + jitter * 0.6)))
            else:
                rv = int(255 * (0.5 + 0.5 * math.cos(2.6 * rad + jitter * 0.3)))
                gv = int(255 * (0.5 + 0.5 * math.sin(3.1 * rad * 2.0 + jitter * 0.3)))
                bv = int(255 * (0.3 + 0.7 * (u if (int(r / 8) + int(c / 8)) % 2 else 1 - u)))
            # checkerboard alpha band so transparency is exercised
            a = 255
            if (int(r / 5) + int(c / 5)) % 4 == 0:
                a = int(255 * (0.25 + 0.35 * math.sin(u * 2.0 + v)))
            out[(r, c)] = (rv, gv, bv, a)
    return out


def to_gray(rgba):
    r, g, b = rgba[0], rgba[1], rgba[2]
    return (r * 299 + g * 587 + b * 114) // 1000


def rows_from(rgba, w, h, fmt):
    if fmt == "rgba":
        return [bytes(v for cc in range(w) for v in rgba[(rr, cc)]) for rr in range(h)]
    if fmt == "rgb":
        return [bytes(v for cc in range(w) for v in rgba[(rr, cc)][:3]) for rr in range(h)]
    if fmt == "gray":
        return [bytes([to_gray(rgba[(rr, cc)]) for cc in range(w)]) for rr in range(h)]
    if fmt == "gray16":
        return [b"".join(struct.pack(">H", to_gray(rgba[(rr, cc)]) * 257) for cc in range(w))
                for rr in range(h)]
    raise ValueError(fmt)


def emit(dirpath, files):
    os.makedirs(dirpath, exist_ok=True)
    for f in os.listdir(dirpath):
        p = os.path.join(dirpath, f)
        if os.path.isfile(p):
            os.remove(p)
    pal = b"".join(struct.pack("3B", (i * 7) & 255, (i * 13) & 255, (i * 29) & 255)
                   for i in range(16))
    for fname, w, h, seed in files:
        rgba = pattern(w, h, seed)
        fmt = fname.rsplit(".", 1)[1]
        stem = fname.rsplit(".", 1)[0]
        if fmt == "png" and "pal" in stem:
            idx = []
            for r in range(h):
                row = bytearray()
                for c in range(w):
                    px = rgba[(r, c)]
                    # 16-entry palette: 4x4 quantisation of red/green
                    i = ((px[0] >> 6) << 2) | (px[1] >> 6)
                    if px[3] < 128:
                        i = 0
                    row.append(i)
                idx.append(bytes(row))
            trns = bytes((0 if i == 0 else 255) for i in range(16))
            write_png(os.path.join(dirpath, fname), w, h, 8, 3, idx, pal, trns)
        elif fmt == "png" and "gray16" in stem:
            write_png(os.path.join(dirpath, fname), w, h, 16, 0, rows_from(rgba, w, h, "gray16"))
        elif fmt == "png" and "gray" in stem:
            write_png(os.path.join(dirpath, fname), w, h, 8, 0, rows_from(rgba, w, h, "gray"))
        elif fmt == "png" and "rgb" in stem:
            write_png(os.path.join(dirpath, fname), w, h, 8, 2, rows_from(rgba, w, h, "rgb"))
        elif fmt == "png":
            write_png(os.path.join(dirpath, fname), w, h, 8, 6, rows_from(rgba, w, h, "rgba"))
        elif fmt == "bmp":
            write_bmp24(os.path.join(dirpath, fname), w, h, rgba)
        elif fmt == "tga":
            write_tga24(os.path.join(dirpath, fname), w, h, rgba)
        else:
            raise ValueError(fmt)


def corrupt(src_dir, dst_dir):
    """Add a truncated-at-47%% and a garbage variant of each valid file.

    PNG and BMP truncations are rejected or clamped deterministically by stb's
    decoders.  TGA truncation is NOT: the loader reads into uninitialized
    memory, so a truncated TGA is nondeterministic across binaries and
    ungradeable.  TGA files therefore only get the garbage variant.
    """
    for f in sorted(os.listdir(src_dir)):
        p = os.path.join(src_dir, f)
        if not os.path.isfile(p):
            continue
        if "-cut" in f or "-garbage" in f:
            continue
        stem = f.rsplit(".", 1)[0]
        ext = f.rsplit(".", 1)[1]
        if ext == "tga":
            with open(os.path.join(dst_dir, stem + "-garbage." + ext), "wb") as out:
                out.write((f"this is not an image: {f} just noise bytes, "
                           "not a valid raster of any sort. " * 40).encode())
            continue
        data = open(p, "rb").read()
        with open(os.path.join(dst_dir, stem + "-cut." + ext), "wb") as out:
            out.write(data[: max(16, int(len(data) * 0.47))])
        with open(os.path.join(dst_dir, stem + "-garbage." + ext), "wb") as out:
            out.write((f"this is not an image: {f} just noise bytes, "
                       "not a valid raster of any sort. " * 40).encode())


def main():
    # visible sample set
    emit(VIS, [
        ("swirl.png", 64, 64, 11),
        ("blocks.bmp", 50, 37, 23),
        ("filmstrip.tga", 80, 24, 47),
        ("garden.png", 44, 33, 59),   # palette
        ("gear.rgb.png", 32, 40, 83), # rgb truecolor
    ])
    # corrupt samples for the visible set
    corrupt(VIS, VIS)
    # hidden cases: different formats/sizes/corruptions
    emit(os.path.join(HIDDEN, "case1"), [
        ("case1-bloom.png", 96, 64, 101),      # rgba
        ("case1-mosaic-pal.png", 57, 71, 137), # palette + tRNS
        ("case1-grains.gray.png", 70, 70, 173),
        ("case1-banner.bmp", 33, 47, 229),
    ])
    corrupt(os.path.join(HIDDEN, "case1"), os.path.join(HIDDEN, "case1"))
    emit(os.path.join(HIDDEN, "case2"), [
        ("case2-deep.gray16.png", 37, 53, 307),
        ("case2-photo.rgb.png", 120, 96, 331),
        ("case2-postcard.tga", 55, 31, 359),
        ("case2-strip.bmp", 29, 29, 421),
        ("case2-haze.png", 61, 43, 443),
    ])
    corrupt(os.path.join(HIDDEN, "case2"), os.path.join(HIDDEN, "case2"))
    emit(os.path.join(HIDDEN, "case3"), [
        ("case3-rainbow.png", 48, 48, 509),
        ("case3-sketch.bmp", 61, 27, 563),
        ("case3-tiny.gray.png", 23, 17, 601),
        ("case3-kaleidoscope.png", 52, 76, 643),
        ("case3-tape.tga", 42, 42, 701),
    ])
    corrupt(os.path.join(HIDDEN, "case3"), os.path.join(HIDDEN, "case3"))
    print("fixtures written")


if __name__ == "__main__":
    main()