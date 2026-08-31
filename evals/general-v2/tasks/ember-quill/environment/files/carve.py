#!/usr/bin/env python3
"""QSFS deleted-file carving tool.

Usage:
    python3 carve.py recover <image> <outdir> [report_json]

Recovers deleted files from a Quill QSFS snapshot image into <outdir>,
byte-exact.  If [report_json] is given, writes a JSON report mapping each
recovered filename to {"size", "version", "sha256"}.
"""
import hashlib
import json
import os
import struct
import sys
import zlib

BS_MIN = 512
SLOT = 128
MAGIC_SB = b"QSF1"
MAGIC_IN = b"QINO"
FLAG_DELETED = 1


def parse_image(img):
    if len(img) < BS_MIN or img[0:4] != MAGIC_SB:
        raise SystemExit("not a QSFS image (bad superblock magic)")
    block_size, inode_area_block, inode_count, extent_area_block = \
        struct.unpack_from("<IIII", img, 4)
    if block_size < BS_MIN or block_size % BS_MIN:
        raise SystemExit("bad block size")
    base = inode_area_block * block_size
    ext_base = extent_area_block * block_size
    inodes = []
    for i in range(inode_count):
        off = base + i * SLOT
        slot = img[off:off + SLOT]
        if len(slot) < SLOT or slot[0:4] != MAGIC_IN:
            continue  # empty or garbage slot
        version, flags, name_len = struct.unpack_from("<III", slot, 4)
        if version < 1 or not (1 <= name_len <= 96):
            continue
        name = slot[16:16 + name_len]
        if len(name) != name_len:
            continue
        size, ext_start, ext_count, crc = struct.unpack_from("<IIII", slot, 112)
        parts = []
        ok = True
        for j in range(ext_count):
            eoff, elen = struct.unpack_from(
                "<II", img, ext_base + (ext_start + j) * 8)
            if elen == 0 or eoff + elen > len(img):
                ok = False
                break
            parts.append(img[eoff:eoff + elen])
        if not ok:
            continue
        content = b"".join(parts)
        if len(content) != size:
            continue  # extent map inconsistent with declared size
        if (zlib.crc32(content) & 0xFFFFFFFF) != crc:
            continue  # stale/corrupt inode copy
        try:
            name_s = name.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if name_s in (".", "..") or "/" in name_s or "\x00" in name_s:
            continue
        inodes.append((name_s, version, flags, content))
    return inodes


def recover(img_path, outdir, report_path=None):
    with open(img_path, "rb") as f:
        img = f.read()
    best = {}
    for name, version, flags, content in parse_image(img):
        if not (flags & FLAG_DELETED):
            continue  # only deleted files are recovered
        cur = best.get(name)
        if cur is None or version > cur[0]:
            best[name] = (version, content)
    os.makedirs(outdir, exist_ok=True)
    for name, (version, content) in sorted(best.items()):
        with open(os.path.join(outdir, name), "wb") as f:
            f.write(content)
    if report_path:
        rep = {
            name: {
                "size": len(content),
                "version": version,
                "sha256": hashlib.sha256(content).hexdigest(),
            }
            for name, (version, content) in best.items()
        }
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(rep, f, indent=2, sort_keys=True)
    for name in sorted(best):
        print("RECOVERED %s" % name)


def main(argv):
    if len(argv) < 4 or argv[1] != "recover":
        sys.stderr.write(__doc__)
        return 2
    recover(argv[2], argv[3], argv[4] if len(argv) > 4 else None)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
