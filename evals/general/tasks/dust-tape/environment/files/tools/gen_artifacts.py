#!/usr/bin/env python3
"""Deterministically generate the dust-tape artifact corpus.

Creates PDP-11 a.out binaries (four magic variants), minimal ELF images
(32/64-bit, both endiannesses, several machines), an MZ stub, text files,
truncated headers and binary junk.
"""
import argparse
import os
import random
import struct

AOUT_MAGICS = {0x0107: "shared", 0x0108: "pure", 0x0109: "sep", 0x010B: "ovl"}


def aout(magic, tsize, dsize, bsize, symsize, entry, trsize, drsize, seed,
         truncate_to=None):
    header = struct.pack("<8H", magic, tsize, dsize, bsize, symsize, entry,
                         trsize, drsize)
    rng = random.Random(seed)
    text = bytes(rng.randrange(1, 16) for _ in range(tsize))
    data = bytes(rng.randrange(32, 127) for _ in range(dsize))
    blob = header + text + data
    if truncate_to is not None:
        blob = blob[:truncate_to]
    return blob


def elf64(machine, data, seed, nbytes=96):
    ident = b"\x7fELF" + bytes([2, data, 1, 0]) + b"\x00" * 8
    fmt = "<HHIQQQIHHHHHH" if data == 1 else ">HHIQQQIHHHHHH"
    e = struct.pack(fmt, 2, machine, 1, 0x00400000 + seed, 0, 64,
                    0, 64, 0, 0, 0, 0, 0)
    body = bytes(random.Random(seed).randrange(0, 256) for _ in range(nbytes - 64))
    return ident + e + body


def elf32(machine, data, seed, nbytes=84):
    ident = b"\x7fELF" + bytes([1, data, 1, 0]) + b"\x00" * 8
    fmt = "<HHIIIIIHHHHHH" if data == 1 else ">HHIIIIIHHHHHH"
    e = struct.pack(fmt, 2, machine, 1, 0x1000 + seed, 0, 52, 0, 52,
                    0, 0, 0, 0, 0)
    body = bytes(random.Random(seed).randrange(0, 256) for _ in range(nbytes - 52))
    return ident + e + body


def write(path, blob):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(blob)
    print("wrote %s (%d bytes)" % (path, len(blob)))


def build(out):
    # NOTE: hidden artifact sets are NOT generated here (they ship as static
    # files under tests/hidden/<set>/artifacts so the agent cannot inspect
    # them from the image). Only the visible archive is generated.
    # ---- visible archive ----
    write(os.path.join(out, "monitor.pdp11"),
          aout(0x0108, 2592, 384, 64, 544, 0, 96, 16, seed=101))
    write(os.path.join(out, "patch.pdp11"),
          aout(0x0107, 128, 0, 32, 0, 64, 8, 0, seed=202))
    write(os.path.join(out, "fsck.elf"), elf64(62, 1, seed=7))
    write(os.path.join(out, "netd.elf"), elf32(40, 1, seed=11))
    write(os.path.join(out, "installer.com"), b"MZ" + b"\x90" * 62)
    write(os.path.join(out, "README.txt"),
          b"Harlow Retro-Computing Society DECtape recovery dump, batch 7.\n"
          b"Files triaged before emulation; do not execute anything.\n")
    write(os.path.join(out, "sector.raw"),
          bytes(random.Random(30303).randrange(0, 256) for _ in range(512)))


def build_hidden(out):
    """Used only at task-authoring time; not invoked by the Dockerfile."""
    a = os.path.join(out, "_hiddenA")
    write(os.path.join(a, "kernel.pdp11"),
          aout(0x0109, 0x0C00, 0x0140, 0x0080, 0x03A0, 0x0000, 0x0040, 0x0020,
               seed=909))
    write(os.path.join(a, "overlay.pdp11"),
          aout(0x010B, 512, 256, 0, 96, 0x40, 0, 0, seed=818))
    write(os.path.join(a, "cut.pdp11"),
          aout(0x0107, 300, 20, 4, 40, 0, 0, 0, seed=616, truncate_to=7))
    write(os.path.join(a, "cross.elf"), elf32(8, 2, seed=21))      # BE MIPS
    write(os.path.join(a, "lisp.bin"), elf64(50, 1, seed=23))      # ia64
    write(os.path.join(a, "notes.txt"), b"drive 3, platter 2, image B\n" * 3)

    # ---- hidden set B ----
    b = os.path.join(out, "_hiddenB")
    write(os.path.join(b, "boot.pdp11"),
          aout(0x0108, 0x0200, 0x0040, 0x0010, 0x0000, 0x0030, 0x0010, 0x0008,
               seed=707))
    write(os.path.join(b, "tiny.pdp11"), aout(0x010B, 8, 0, 0, 0, 0, 0, 0,
                                              seed=505))
    write(os.path.join(b, "host.elf"), elf64(62, 1, seed=31))      # x86_64
    write(os.path.join(b, "weird.elf"), elf64(244, 1, seed=33))    # unknown mach
    write(os.path.join(b, "stub.elf"), b"\x7fELF\x02\x01\x01")     # 7 bytes
    write(os.path.join(b, "empty.bin"), b"")
    write(os.path.join(b, "prog.txt"), b'PRINT "A"\nGOTO 10\nRUN\n')
    write(os.path.join(b, "noise.bin"),
          bytes(random.Random(40404).randrange(0, 256) for _ in range(64)))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    build(args.out)
