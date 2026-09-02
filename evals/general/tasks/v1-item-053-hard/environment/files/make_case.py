#!/usr/bin/env python3
"""Builds a raw image containing a FRAGMENTED deleted PNG.

The target file data/figure.png was stored in 4 fragments whose on-disk block
positions are scattered, and a later defragmentation copy REORDERED the blocks.
The volume journal therefore carries TWO candidate records for that file:

  * a 0x01-marked "stale snapshot" record whose extent list is the scrambled
    order (concatenating in that order yields garbage),
  * a 0x55-marked "authoritative/current" record whose extent list yields the
    true, reassembled PNGF bytes.

The analyst must read the journal, pick the current record, and reassemble the
fragments in the ORDER the current record lists, then confirm the result is a
valid PNG (starts 89 50 4E 47 / ends with the IEND chunk).

Layout (sector = 512, little-endian integers):
  offset 0      : superblock magic "CASEIMG2" (8 bytes)
  offset 8      : sector size, uint64 = 512
  offset 16     : directory offset, uint64
  directory records (fixed 128 bytes each):
    [0]    status          (0x10 allocated, 0xE5 deleted)
    [1]    journal marker  (0x01 stale snapshot, 0x55 current)
    [5]    name length
    [6..37] name (32 bytes NUL-padded)
    [38..56] 4 extents packed as (16 bytes each):
            seq uint32 (LE), offset uint64 (LE), length uint32 (LE)
"""
import struct
import zlib


def make_png(w, h, rgb):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        c += struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        return c

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    raw = bytearray()
    row = w * 3
    for _ in range(h):
        raw.append(0)
        raw += bytes(rgb) * w
    idat = chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


PNG = make_png(40, 30, (0, 102, 204))

SECTOR = 512
SIZE = 16384

# split into 4 fragments at deterministic logical cut points
cuts = [17, 37, 61]
frags = []
start = 0
for c in cuts:
    frags.append(PNG[start:c])
    start = c
frags.append(PNG[start:])
assert b"".join(frags) == PNG

# on-disk scattered offsets for the 4 fragments
ON_DISK = [2048, 6144, 10240, 11264]

img = bytearray(b"\x00" * SIZE)

# fragments are physically stored scattered; insert each at its on-disk offset
for i, frag in enumerate(frags):
    doff = ON_DISK[i]
    img[doff:doff + len(frag)] = frag

# Build the two journal records.
# current: extents listed in the CORRECT (0,1,2,3) order
# stale:   extents listed in a scrambled order
def build_record(status, marker, name, extent_order):
    rec = bytearray(128)
    rec[0] = status
    rec[1] = marker
    rec[5] = len(name)
    rec[6:6 + min(len(name), 30)] = name[:min(len(name), 30)]
    for k, idx in enumerate(extent_order):
        f = frags[idx]
        doff = ON_DISK[idx]
        struct.pack_into("<I", rec, 38 + k * 16, k + 1)          # seq
        struct.pack_into("<Q", rec, 42 + k * 16, doff)           # offset
        struct.pack_into("<I", rec, 50 + k * 16, len(f))         # size
    return bytes(rec)


NAME = b"data/figure.png"
current = build_record(0xE5, 0x55, NAME, [0, 1, 2, 3])
stale = build_record(0xE5, 0x01, NAME, [2, 0, 3, 1])

DIR_OFF = 512
img[DIR_OFF:DIR_OFF + len(stale) + len(current)] = stale + current
img[0:8] = b"CASEIMG2"
struct.pack_into("<Q", img, 8, SECTOR)
struct.pack_into("<Q", img, 16, DIR_OFF)

out = "/workspace/case.dd"
with open(out, "wb") as f:
    f.write(img)

import hashlib
print("wrote", out, len(img), "bytes")
print("png_sha", hashlib.sha256(PNG).hexdigest())
print("image_sha", hashlib.sha256(img).hexdigest())
print("png_len", len(PNG))